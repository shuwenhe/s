package std.terminal
import ("std.result"; "std.prelude")

struct terminal_error { int code }
struct terminal_size { int rows, int columns }
struct output_buffer { int descriptor, int limit, string pending }
struct terminal_session { int generation, bool active }

extern "intrinsic" func __std_byte_string(int value) string
extern "intrinsic" func __std_write(int descriptor, string text, int offset) int
extern "intrinsic" func __std_tty_size(int descriptor) int
extern "intrinsic" func __std_terminal_enter(int descriptor) int
extern "intrinsic" func __std_terminal_leave(int generation) int

func escape() string { return __std_byte_string(27) }
func reset_color() string { return escape() + "[0m" }
func clear_screen() string { return escape() + "[2J" + escape() + "[H" }
func cursor_visible(bool visible) string {
    if visible { return escape() + "[?25h" }
    return escape() + "[?25l"
}
func alternate_screen(bool enabled) string {
    if enabled { return escape() + "[?1049h" }
    return escape() + "[?1049l"
}
func color(int foreground, int background, bool bright) (string, terminal_error) {
    if foreground < 0 || foreground > 7 || background < 0 || background > 7 {
        return "", terminal_error { code: 22 }
    }
    weight := "0"
    if bright { weight = "1" }
    return escape() + "[" + weight + ";" + std.prelude.to_string(30 + foreground)
        + ";" + std.prelude.to_string(40 + background) + "m", terminal_error { code: 0 }
}
func cursor_position(int row, int column) (string, terminal_error) {
    if row < 1 || row > 65535 || column < 1 || column > 65535 { return "", terminal_error { code: 22 } }
    return escape() + "[" + std.prelude.to_string(row) + ";" + std.prelude.to_string(column) + "H", terminal_error { code: 0 }
}
func dimensions(int descriptor) (terminal_size, terminal_error) {
    if descriptor < 0 || descriptor > 2147483647 { return terminal_size { rows: 0, columns: 0 }, terminal_error { code: 22 } }
    packed := __std_tty_size(descriptor)
    if packed < 0 { return terminal_size { rows: 0, columns: 0 }, terminal_error { code: 0 - packed } }
    return terminal_size { rows: packed >> 32, columns: packed & 4294967295 }, terminal_error { code: 0 }
}
func new_buffer(int descriptor, int limit) (output_buffer, terminal_error) {
    if descriptor < 0 || descriptor > 2147483647 || limit <= 0 || limit > 1048576 {
        return output_buffer { descriptor: descriptor, limit: 0, pending: "" }, terminal_error { code: 22 }
    }
    return output_buffer { descriptor: descriptor, limit: limit, pending: "" }, terminal_error { code: 0 }
}
func buffer_append(output_buffer* output, string text) terminal_error {
    if output.limit <= 0 || output.limit > 1048576 || len(output.pending) > output.limit { return terminal_error { code: 22 } }
    if len(text) > output.limit - len(output.pending) { return terminal_error { code: 75 } }
    output.pending = output.pending + text
    return terminal_error { code: 0 }
}
func flush(output_buffer* output) terminal_error {
    if output.descriptor < 0 || output.descriptor > 2147483647 || output.limit <= 0 || output.limit > 1048576 || len(output.pending) > output.limit { return terminal_error { code: 22 } }
    consumed := 0
    while consumed < len(output.pending) {
        count := __std_write(output.descriptor, output.pending, consumed)
        if count <= 0 || count > len(output.pending) - consumed {
            code := 5
            if count < 0 { code = 0 - count }
            if consumed > 0 { output.pending = std.prelude.prelude_slice(output.pending, consumed, len(output.pending)) }
            return terminal_error { code: code }
        }
        consumed = consumed + count
    }
    output.pending = ""
    return terminal_error { code: 0 }
}
func initialize(int descriptor) (terminal_session, terminal_error) {
    size, error := dimensions(descriptor)
    if error.code != 0 { return terminal_session { generation: 0, active: false }, error }
    token := __std_terminal_enter(descriptor)
    if token < 0 { return terminal_session { generation: 0, active: false }, terminal_error { code: 0 - token } }
    output, buffer_error := new_buffer(descriptor, 128)
    sequence := alternate_screen(true) + cursor_visible(false) + clear_screen()
    buffer_error = buffer_append(output*, sequence)
    if buffer_error.code == 0 { buffer_error = flush(output*) }
    if buffer_error.code != 0 {
        ignored := __std_terminal_leave(token)
        return terminal_session { generation: 0, active: false }, buffer_error
    }
    return terminal_session { generation: token, active: true }, terminal_error { code: 0 }
}
func restore(terminal_session* session) terminal_error {
    if !session.active { return terminal_error { code: 0 } }
    status := __std_terminal_leave(session.generation)
    if status < 0 { return terminal_error { code: 0 - status } }
    session.active = false
    return terminal_error { code: 0 }
}
