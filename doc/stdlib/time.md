# std.time — Linux/amd64

Source: `src/std/time.s`. This package uses kernel `clock_gettime` and `nanosleep`, not busy loops or subprocesses. The shared OS boundary follows the Linux x86-64 syscall ABI; the seed adapts tagged integers at its boundary while canonical native code uses raw int64 values.

## API

| Declaration | Contract |
|---|---|
| `struct time_error { int code }` | 0 success; positive errno on failure |
| `struct timespec { int seconds, int nanoseconds }` | Nonnegative seconds; nanoseconds in [0, 1000000000) |
| `struct duration { int nanoseconds }` | Int64 duration value; elapsed API yields nonnegative values |
| `sleep_ms(int milliseconds) time_error` | Block for at least requested interval; negative EINVAL (22), conversion overflow EOVERFLOW (75) |
| `sleep_ns(int nanoseconds) time_error` | Same contract in nanoseconds; negative EINVAL |
| `nanosleep(timespec request) time_error` | Validate timespec and int64 total range; retry EINTR using remaining interval |
| `wall_clock() (int, time_error)` | Nanoseconds since Unix epoch using CLOCK_REALTIME; wall time can change |
| `monotonic_clock() (int, time_error)` | CLOCK_MONOTONIC nanoseconds; use for durations, not civil timestamps |
| `timer_start() (timer, time_error)` | Capture monotonic start; mark initialized only on success |
| `timer_reset(timer* value) time_error` | Reset start on success; failed clock call preserves previous timer |
| `elapsed_time(timer value) (duration, time_error)` | Checked monotonic difference; uninitialized/negative/future start is EINVAL |
| `duration.milliseconds() int`, `duration.seconds() int` | Integer division/truncation; no floating-point requirement |

The maximum represented interval is 9223372036854775807 ns. `sleep_ms` accepts at most 9223372036854 ms. `nanosleep` rejects total intervals exceeding that bound before entering the kernel. Kernel failures propagate; raw negative errno is converted to positive typed error at the S boundary.

Clock timestamps must fit nonnegative int64 nanoseconds. Pre-epoch or post-range realtime values produce EOVERFLOW. Clock precision and scheduling granularity depend on the kernel/host; a nanosecond unit does not promise nanosecond accuracy. Sleep can overrun because scheduling is not real time. Relative sleeps restart remaining time after EINTR; a long signal storm can introduce delay. CLOCK_MONOTONIC excludes suspended time on Linux. Calendar parsing/formatting, timezones and asynchronous timers are not implemented by this API.

```s
package main
import "std.time"
func main() int {
    started, error := std.time.timer_start()
    if error.code != 0 { return error.code }
    error = std.time.sleep_ms(20)
    if error.code != 0 { return error.code }
    elapsed, error := std.time.elapsed_time(started)
    if error.code != 0 { return error.code }
    if elapsed.milliseconds() < 20 { return 1 }
    return 0
}
```

Until public import orchestration is installed, explicitly pass `src/std/time.s` with the application to `bin/s_compiler --compile-unit out.sasm ...`, then `--emit-bin out.sasm program`. The example does not imply old installed compilers already recognize new intrinsic names.

Acceptance: `python3 test/stdlib-native/test_time.py -v` compiles and executes real S ELF programs, checks wall/monotonic/timer/range behavior, records measured wall/CPU time, exercises the standalone seed and injects EINTR/EIO using strace. Tracing permission is required; failed tracing is a test failure, never a skipped assertion.

Kernel contracts: [nanosleep](https://man7.org/linux/man-pages/man2/nanosleep.2.html) and [clock_gettime](https://man7.org/linux/man-pages/man2/clock_gettime.2.html).
