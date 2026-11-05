# std.input

Development API; Linux x86-64. Import `"std.input"`.

- `raw_mode(int descriptor) (input_session, input_error)` saves kernel termios and applies raw byte input. Only one active process-wide raw session is allowed (EBUSY 16). Non-terminals return ENOTTY 25.
- `restore(input_session*) input_error` restores original settings exactly; inactive handles are idempotent. Failed restoration leaves the session active for retry. Do not duplicate active session handles.
- `new_reader(int descriptor) (reader, input_error)` creates independent parser state. Descriptors must be 0–2147483647. Keep them open and unchanged during use.
- `read_blocking(reader*)` and `read_nonblocking(reader*)` return `(key_event, input_error)`. Error code zero means success; positive codes are Linux errno. `none` means no input available; `eof` is persistent end of input, distinct from errors.
- `read_key(reader*, bool blocking)` is the shared implementation. `decode_key(string)` decodes a complete key, and `input_event(string)` constructs an empty event.

Events contain `string kind`, `string text` (original bytes), and `int code` (byte value, or final sequence byte). Kinds are `up`, `down`, `left`, `right`, `key`, `escape`, `unknown`, `none`, `eof`. WASD in either case maps to directions. CSI/SS3 arrow sequences map to directions; CSI numeric/semicolon modifiers are accepted. Other sequences remain unknown. NUL is a valid key with code zero; text is bytes, not a UTF-8 character decoder.

A lone ESC waits up to 25 ms on the monotonic clock. Nonblocking calls retain partial sequences and never wait for completion. Sequences are bounded to 32 stored bytes; oversized sequences emit one unknown event and discard through the final byte, with at most 256 discarded bytes per call. A call may therefore return `none` while discarding malformed input. Readers own their pending S string and mutable parser state; do not edit fields between calls. Poll retries interruptions against an absolute deadline rather than restarting the original wait. Blocking input sleeps in the kernel.

Restore explicitly before closing/replacing the descriptor. Runtime cleanup on normal entry-point return also restores raw mode, including handled read errors and nonzero exit status. Unhandled fatal signals/forced termination and concurrent readers on the same descriptor are outside this initial contract. Ctrl-C is delivered as byte 3 in raw mode; applications choose how to handle it.

`python3 test/stdlib-native/test_input.py -v` compiles real native ELF and seed executables, checks arrows/WASD/NUL/EOF, fragmented ESC/timeouts, oversized/unknown sequences, prompt nonblocking return, PTY raw settings and exact restoration, handled EIO, and low CPU use while waiting. Fault injection requires ptrace permission.
