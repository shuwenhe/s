package std.time
import "std.result"

// Linux/amd64. Positive errno on failure; code zero denotes success.
struct time_error { int code }
struct timespec { int seconds, int nanoseconds }
struct duration { int nanoseconds }
struct timer { int started_ns, bool initialized }

extern "intrinsic" func __std_clock_ns(int clock_id) int
extern "intrinsic" func __std_nanosleep(int seconds, int nanoseconds) int

func nanosleep(timespec request) time_error {
    if request.seconds < 0 || request.nanoseconds < 0 || request.nanoseconds >= 1000000000 {
        return time_error { code: 22 }
    }
    if request.seconds > 9223372036 || (request.seconds == 9223372036 && request.nanoseconds > 854775807) {
        return time_error { code: 75 }
    }
    status := __std_nanosleep(request.seconds, request.nanoseconds)
    return time_error { code: 0 - status }
}

func sleep_ns(int nanoseconds) time_error {
    if nanoseconds < 0 { return time_error { code: 22 } }
    return nanosleep(timespec { seconds: nanoseconds / 1000000000, nanoseconds: nanoseconds % 1000000000 })
}

func sleep_ms(int milliseconds) time_error {
    if milliseconds < 0 { return time_error { code: 22 } }
    if milliseconds > 9223372036854 { return time_error { code: 75 } }
    return sleep_ns(milliseconds * 1000000)
}

func wall_clock() (int, time_error) {
    value := __std_clock_ns(0)
    if value < 0 { return 0, time_error { code: 0 - value } }
    return value, time_error { code: 0 }
}

func monotonic_clock() (int, time_error) {
    value := __std_clock_ns(1)
    if value < 0 { return 0, time_error { code: 0 - value } }
    return value, time_error { code: 0 }
}

func timer_start() (timer, time_error) {
    value, error := monotonic_clock()
    return timer { started_ns: value, initialized: error.code == 0 }, error
}

func timer_reset(timer* value) time_error {
    now, error := monotonic_clock()
    if error.code != 0 { return error }
    value.started_ns = now
    value.initialized = true
    return error
}

func elapsed_time(timer value) (duration, time_error) {
    if !value.initialized || value.started_ns < 0 { return duration { nanoseconds: 0 }, time_error { code: 22 } }
    now, error := monotonic_clock()
    if error.code != 0 { return duration { nanoseconds: 0 }, error }
    if now < value.started_ns { return duration { nanoseconds: 0 }, time_error { code: 22 } }
    return duration { nanoseconds: now - value.started_ns }, error
}

func (std.time.duration value) milliseconds() int { return value.nanoseconds / 1000000 }
func (std.time.duration value) seconds() int { return value.nanoseconds / 1000000000 }
