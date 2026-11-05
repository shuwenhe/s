# std.terminal

Development API; Linux x86-64, ANSI-compatible terminals. Import `"std.terminal"`.

| API | Result / contract |
|---|---|
| `escape`, `reset_color`, `clear_screen` | ANSI strings; clear includes home cursor |
| `cursor_visible(bool)`, `alternate_screen(bool)` | ANSI strings only; caller writes them |
| `color(int foreground, int background, bool bright)` | `(string, terminal_error)`; colors 0–7 |
| `cursor_position(int row, int column)` | `(string, terminal_error)`; coordinates 1–65535 |
| `dimensions(int descriptor)` | `(terminal_size, terminal_error)`; actual TIOCGWINSZ rows/columns; zero dimensions rejected |
| `new_buffer(int descriptor, int limit)` | `(output_buffer, terminal_error)`; limit 1–1048576 bytes |
| `buffer_append(output_buffer*, string)` | bounded append; overflow preserves pending bytes |
| `flush(output_buffer*)` | retries EINTR/short writes; failure retains exactly the unsent suffix |
| `initialize(int descriptor)` | `(terminal_session, terminal_error)`; enters alternate screen, hides cursor, clears once |
| `restore(terminal_session*)` | restores cursor and main screen; repeated restore of inactive handle succeeds |

Errors have `int code`: zero success, positive Linux errno, including EINVAL 22, EOVERFLOW 75, EBUSY 16, ENOTTY 25. Descriptor range is 0–2147483647. Buffer values own S strings with existing snapshot semantics. Session handles represent one process-global output session; do not copy an active handle and restore both copies. Stale tokens fail. Failed restoration keeps the handle active for retry.

Compute strings before passing an exclusive output borrow to `buffer_append`. Initialization validates the terminal before emitting ANSI bytes. Broken pipes return EPIPE without terminating the process; the write bridge preserves the caller's signal mask and pre-existing pending SIGPIPE. Allocation failure in the tagged seed bridge returns ENOMEM.

Normal entry-point return invokes runtime cleanup, preserving the program exit status. Explicit restoration is recommended for observable errors. Abrupt signals, forced termination, descriptor replacement and concurrent session manipulation are outside this initial single-threaded contract. ANSI reset does not restore arbitrary pre-existing terminal color/cursor configuration.

`python3 test/stdlib-native/test_terminal.py -v` executes native ELF and tagged seed paths: PTY dimensions/cleanup, ANSI bytes, bounds, EINTR/EIO, real partial nonblocking writes, EPIPE and exact signal-state preservation, allocator failure, nonzero exit status.
