package main
import ("std.terminal"; "std.prelude")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    mode := "buffer"
    if len(args) > 1 { mode = args[1] }
    if mode == "dimensions" {
        size, error := std.terminal.dimensions(1)
        if error.code != 0 { return error.code }
        println(std.prelude.to_string(size.rows) + "x" + std.prelude.to_string(size.columns))
        return 0
    }
    if mode == "session" || mode == "explicit" {
        session, error := std.terminal.initialize(1)
        if error.code != 0 { return error.code }
        if mode == "explicit" {
            if std.terminal.restore(session*).code != 0 { return 40 }
            if std.terminal.restore(session*).code != 0 { return 41 }
        }
        return 0
    }
    if mode == "not-tty" {
        ignored, error := std.terminal.initialize(1)
        if error.code != 25 { return 42 }
        return 0
    }
    output, error := std.terminal.new_buffer(1, 128)
    if error.code != 0 { return 1 }
    if std.terminal.buffer_append(output*, "abcdefgh").code != 0 { return 2 }
    if mode == "io-error" || mode == "closed-pipe" {
        error = std.terminal.flush(output*)
        expected := 5
        if mode == "closed-pipe" { expected = 32 }
        if error.code != expected || output.pending != "abcdefgh" { return 43 }
        return 0
    }
    output.pending = ""
    position, position_error := std.terminal.cursor_position(3, 5)
    if position_error.code != 0 { return 3 }
    color, color_error := std.terminal.color(1, 4, true)
    if color_error.code != 0 { return 4 }
    sequence := std.terminal.clear_screen() + position + color + "S" + std.terminal.reset_color()
    if std.terminal.buffer_append(output*, sequence).code != 0 { return 5 }
    if std.terminal.flush(output*).code != 0 || output.pending != "" { return 6 }
    ignored, invalid := std.terminal.cursor_position(0, 1)
    if invalid.code != 22 { return 7 }
    ignored_color, invalid_color := std.terminal.color(8, 0, false)
    if invalid_color.code != 22 { return 8 }
    small, small_error := std.terminal.new_buffer(1, 8)
    if small_error.code != 0 { return 9 }
    if std.terminal.buffer_append(small*, "12345678").code != 0 { return 10 }
    if std.terminal.buffer_append(small*, "9").code != 75 || small.pending != "12345678" { return 11 }
    return 0
}
