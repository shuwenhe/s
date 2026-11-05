package std.input
import ("std.result"; "std.prelude")

struct input_error { int code }
struct input_event { string kind, int code }
struct input_reader { int descriptor, string buffer, int buffer_pos, int buffer_len, bool eof }
struct input_session { int generation, bool active }

extern "intrinsic" func __std_byte_string(int value) string
extern "intrinsic" func __std_read(int descriptor, int max_bytes) (string, int)
extern "intrinsic" func __std_input_raw_mode(int descriptor) int
extern "intrinsic" func __std_input_restore_mode(int generation) int

func new_reader(int descriptor) (input_reader, input_error) {
    if descriptor < 0 || descriptor > 2147483647 {
        return input_reader { descriptor: descriptor, buffer: "", buffer_pos: 0, buffer_len: 0, eof: false }, input_error { code: 22 }
    }
    return input_reader { descriptor: descriptor, buffer: "", buffer_pos: 0, buffer_len: 0, eof: false }, input_error { code: 0 }
}

func raw_mode(int descriptor) (input_session, input_error) {
    if descriptor < 0 || descriptor > 2147483647 {
        return input_session { generation: 0, active: false }, input_error { code: 22 }
    }
    token := __std_input_raw_mode(descriptor)
    if token < 0 { return input_session { generation: 0, active: false }, input_error { code: 0 - token } }
    return input_session { generation: token, active: true }, input_error { code: 0 }
}

func restore(input_session* session) input_error {
    if !session.active { return input_error { code: 0 } }
    status := __std_input_restore_mode(session.generation)
    if status < 0 { return input_error { code: 0 - status } }
    session.active = false
    return input_error { code: 0 }
}

func byte_at_pos(string buffer, int pos) int {
    if pos < 0 || pos >= len(buffer) { return 0 }
    byte_val := buffer[pos]
    return byte_val
}

func read_nonblocking(input_reader* reader) (input_event, input_error) {
    if reader.eof {
        return input_event { kind: "eof", code: 0 }, input_error { code: 0 }
    }
    
    if reader.buffer_pos >= reader.buffer_len {
        data, status := __std_read(reader.descriptor, 4096)
        bytes_read := status
        if bytes_read < 0 {
            code := 5
            code = 0 - bytes_read
            if code != 11 {
                return input_event { kind: "", code: 0 }, input_error { code: code }
            }
            return input_event { kind: "none", code: 0 }, input_error { code: 0 }
        }
        zero := 0
        if bytes_read <= zero {
            reader.eof = true
            return input_event { kind: "eof", code: 0 }, input_error { code: 0 }
        }
        reader.buffer = data
        reader.buffer_pos = 0
        reader.buffer_len = bytes_read
    }
    
    if reader.buffer_pos >= reader.buffer_len {
        return input_event { kind: "none", code: 0 }, input_error { code: 0 }
    }
    
    pos := reader.buffer_pos
    byte_int := byte_at_pos(reader.buffer, pos)
    reader.buffer_pos = reader.buffer_pos + 1
    
    esc_code := 27
    zero_code := 0
    w_code := 119
    a_code := 97
    s_code := 115
    d_code := 100
    
    if byte_int == esc_code {
        escape_result := parse_escape_sequence(reader)
        if escape_result.kind == "" {
            return input_event { kind: "escape", code: 27 }, input_error { code: 0 }
        }
        return escape_result, input_error { code: 0 }
    }
    
    if byte_int == zero_code {
        return input_event { kind: "key", code: 0 }, input_error { code: 0 }
    }
    
    if byte_int == w_code { return input_event { kind: "up", code: 65 }, input_error { code: 0 } }
    if byte_int == a_code { return input_event { kind: "left", code: 68 }, input_error { code: 0 } }
    if byte_int == s_code { return input_event { kind: "down", code: 66 }, input_error { code: 0 } }
    if byte_int == d_code { return input_event { kind: "right", code: 67 }, input_error { code: 0 } }
    
    return input_event { kind: "key", code: byte_int }, input_error { code: 0 }
}

func parse_escape_sequence(input_reader* reader) input_event {
    if reader.buffer_pos >= reader.buffer_len {
        return input_event { kind: "", code: 0 }
    }
    
    next_byte_int := byte_at_pos(reader.buffer, reader.buffer_pos)
    bracket_code := 91
    
    if next_byte_int != bracket_code {
        return input_event { kind: "", code: 0 }
    }
    
    reader.buffer_pos = reader.buffer_pos + 1
    
    if reader.buffer_pos >= reader.buffer_len {
        return input_event { kind: "", code: 0 }
    }
    
    arrow_byte_int := byte_at_pos(reader.buffer, reader.buffer_pos)
    reader.buffer_pos = reader.buffer_pos + 1
    
    a_arrow := 65
    b_arrow := 66
    c_arrow := 67
    d_arrow := 68
    
    if arrow_byte_int == a_arrow { return input_event { kind: "up", code: 65 } }
    if arrow_byte_int == b_arrow { return input_event { kind: "down", code: 66 } }
    if arrow_byte_int == c_arrow { return input_event { kind: "right", code: 67 } }
    if arrow_byte_int == d_arrow { return input_event { kind: "left", code: 68 } }
    
    return input_event { kind: "", code: 0 }
}

func read_blocking(input_reader* reader) (input_event, input_error) {
    timeout_count := 0
    max_timeout := 10000
    
    for timeout_count < max_timeout {
        event, error := read_nonblocking(reader)
        if error.code != 0 { return event, error }
        if event.kind != "none" { return event, error }
        
        data, status := __std_read(reader.descriptor, 1)
        bytes_read := status
        zero := 0
        if bytes_read <= zero {
            reader.eof = true
            return input_event { kind: "eof", code: 0 }, input_error { code: 0 }
        }
        if bytes_read < 0 {
            code := 0 - bytes_read
            return input_event { kind: "", code: 0 }, input_error { code: code }
        }
        reader.buffer = data
        reader.buffer_pos = 0
        reader.buffer_len = bytes_read
        timeout_count = timeout_count + 1
    }
    
    return input_event { kind: "", code: 0 }, input_error { code: 24 }
}
