package std.input
// Seed tuple lowering uses the standard result layout.
import "std.result"

struct input_error { int code }
struct input_session { int descriptor, int generation, bool active }
struct key_event { string kind, string text, int code }
struct reader { int descriptor, string pending, int escape_started_ns, bool eof, bool discarding }

extern "intrinsic" func __std_raw_enter(int descriptor) int
extern "intrinsic" func __std_raw_leave(int generation) int
extern "intrinsic" func __std_read_byte(int descriptor, int timeout_ms) int
extern "intrinsic" func __std_clock_ns(int clock_id) int
extern "intrinsic" func __std_byte_string(int value) string
extern "intrinsic" func __host_byte_at(string text, int index) int
extern "intrinsic" func __string_slice(string text, int start, int end) string

func raw_mode(int descriptor) (input_session, input_error) {
    if descriptor < 0 || descriptor > 2147483647 {
        return input_session { descriptor: descriptor, generation: 0, active: false }, input_error { code: 22 }
    }
    token := __std_raw_enter(descriptor)
    if token < 0 { return input_session { descriptor: descriptor, generation: 0, active: false }, input_error { code: 0 - token } }
    return input_session { descriptor: descriptor, generation: token, active: true }, input_error { code: 0 }
}

func restore(input_session* session) input_error {
    if !session.active { return input_error { code: 0 } }
    status := __std_raw_leave(session.generation)
    if status < 0 { return input_error { code: 0 - status } }
    session.active = false
    return input_error { code: 0 }
}

func new_reader(int descriptor) (reader, input_error) {
    value := reader { descriptor: descriptor, pending: "", escape_started_ns: 0, eof: false, discarding: false }
    if descriptor < 0 || descriptor > 2147483647 { return value, input_error { code: 22 } }
    return value, input_error { code: 0 }
}

func input_event(string kind) key_event { return key_event { kind: kind, text: "", code: 0 } }

func is_valid_escape_sequence(string text) bool {
    if len(text) < 2 { return false }
    first := __host_byte_at(text, 0)
    if first != 27 { return false }
    second := __host_byte_at(text, 1)
    
    // ESC followed by something other than [ or O is just an escape key
    if second != 91 && second != 79 { return false }
    
    // ESC O requires exactly 2 more bytes: ESC O X
    if second == 79 { return len(text) == 3 }
    
    // ESC [ requires: ESC [ [parameters] terminator
    // Parameters are 0-9 and semicolon (;)
    // Terminator is a letter (64-126)
    if second == 91 {
        if len(text) < 3 { return false }
        last := __host_byte_at(text, len(text) - 1)
        if last < 64 || last > 126 { return false }
        
        // Check all middle characters are digits or semicolons
        index := 2
        while index < len(text) - 1 {
            byte_val := __host_byte_at(text, index)
            if (byte_val < 48 || byte_val > 57) && byte_val != 59 { return false }
            index = index + 1
        }
        return true
    }
    
    return false
}

func decode_key(string text) key_event {
    if len(text) == 0 { return input_event("none") }
    first := __host_byte_at(text, 0)
    last := __host_byte_at(text, len(text) - 1)
    kind := "key"
    
    if first == 27 {
        if len(text) == 1 { return key_event { kind: "escape", text: text, code: 27 } }
        
        kind = "unknown"
        
        if is_valid_escape_sequence(text) {
            if last == 65 { kind = "up" }
            if last == 66 { kind = "down" }
            if last == 67 { kind = "right" }
            if last == 68 { kind = "left" }
        }

        return key_event { kind: kind, text: text, code: last }
    }
    
    // Non-escape characters: check for WASD mapping
    if first == 119 || first == 87 { kind = "up" }
    if first == 97 || first == 65 { kind = "left" }
    if first == 115 || first == 83 { kind = "down" }
    if first == 100 || first == 68 { kind = "right" }
    return key_event { kind: kind, text: text, code: first }
}

func read_key(reader* state, bool blocking) (key_event, input_error) {
    if state.descriptor < 0 || state.descriptor > 2147483647 || len(state.pending) > 32 {
        return input_event("none"), input_error { code: 22 }
    }
    
    drained := 0
    while true {
        // Process pending buffer first
        if len(state.pending) > 0 {
            first := __host_byte_at(state.pending, 0)
            
            // If we're discarding bytes from an oversized sequence, skip until we hit a terminator
            if state.discarding {
                if first >= 64 && first <= 126 { 
                    state.discarding = false 
                    state.pending = __string_slice(state.pending, 1, len(state.pending))
                } else {
                    state.pending = __string_slice(state.pending, 1, len(state.pending))
                }
                continue
            }
            
            // Non-escape characters are emitted immediately
            if first != 27 {
                text := __string_slice(state.pending, 0, 1)
                state.pending = __string_slice(state.pending, 1, len(state.pending))
                return decode_key(text), input_error { code: 0 }
            }
            
            // This is an escape character
            if len(state.pending) > 1 {
                second := __host_byte_at(state.pending, 1)
                
                // ESC not followed by [ or O is a standalone escape
                if second != 91 && second != 79 {
                    state.pending = __string_slice(state.pending, 1, len(state.pending))
                    return key_event { kind: "escape", text: __std_byte_string(27), code: 27 }, input_error { code: 0 }
                }
                
                // We have ESC[ or ESC0, wait for completion
                if len(state.pending) >= 3 {
                    last := __host_byte_at(state.pending, len(state.pending) - 1)
                    
                    // If we reach 32 bytes while still in escape mode (no terminator), mark for discard
                    if len(state.pending) == 32 && (last < 64 || last > 126) {
                        text := state.pending
                        state.pending = ""
                        state.discarding = true
                        return decode_key(text), input_error { code: 0 }
                    }
                    
                    // Complete escape sequence detected (ends with terminator)
                    if last >= 64 && last <= 126 {
                        text := state.pending
                        state.pending = ""
                        return decode_key(text), input_error { code: 0 }
                    }
                }
            }
        }
        
        // Handle EOF
        if state.eof {
            if len(state.pending) > 0 {
                text := state.pending
                state.pending = ""
                return decode_key(text), input_error { code: 0 }
            }
            return input_event("eof"), input_error { code: 0 }
        }
        
        // Calculate read timeout for escape sequence timeout
        timeout := 0
        if blocking { timeout = -1 }
        if len(state.pending) > 0 {
            now := __std_clock_ns(1)
            if now < 0 { return input_event("none"), input_error { code: 0 - now } }
            if state.escape_started_ns < 0 || state.escape_started_ns > now { return input_event("none"), input_error { code: 22 } }
            elapsed := now - state.escape_started_ns
            if elapsed >= 25000000 {
                text := state.pending
                state.pending = ""
                return decode_key(text), input_error { code: 0 }
            }
            if blocking { timeout = (25000000 - elapsed + 999999) / 1000000 }
        }
        
        // Read next byte
        byte := __std_read_byte(state.descriptor, timeout)
        if byte == -4096 { state.eof = true; continue }
        if byte == -11 {
            if !blocking { return input_event("none"), input_error { code: 0 } }
            continue
        }
        if byte < 0 { return input_event("none"), input_error { code: 0 - byte } }
        
        // If we're still discarding bytes from an oversized sequence, skip until terminator
        if state.discarding {
            if byte >= 64 && byte <= 126 {
                state.discarding = false
            }
            continue
        }
        
        if state.discarding {
            if byte >= 64 && byte <= 126 { state.discarding = false }
            drained = drained + 1
            if drained >= 256 { return input_event("none"), input_error { code: 0 } }
            continue
        }

        // Emit immediate byte if not starting escape sequence
        if len(state.pending) == 0 && byte != 27 { return decode_key(__std_byte_string(byte)), input_error { code: 0 } }
        
        // Starting or continuing escape sequence
        if len(state.pending) == 0 {
            now := __std_clock_ns(1)
            if now < 0 { return input_event("none"), input_error { code: 0 - now } }
            state.escape_started_ns = now
        }
        
        state.pending = state.pending + __std_byte_string(byte)
    }
    
    return input_event("none"), input_error { code: 0 }
}

func read_blocking(reader* state) (key_event, input_error) { return read_key(state*, true) }
func read_nonblocking(reader* state) (key_event, input_error) { return read_key(state*, false) }
