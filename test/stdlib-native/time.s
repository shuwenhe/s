package main
import ("std.time"; "std.prelude")

extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    mode := 0
    if len(args) > 1 {
        if args[1] == "1" { mode = 1 }
        if args[1] == "2" { mode = 2 }
        if args[1] == "3" { mode = 3 }
        if args[1] == "4" { mode = 4 }
        if args[1] == "5" { mode = 5 }
    }
    if mode == 1 {
        ignored, failure := std.time.wall_clock()
        if failure.code != 5 { return 31 }
        return 0
    }
    if mode == 2 {
        failure := std.time.sleep_ms(10)
        if failure.code != 5 { return 32 }
        return 0
    }
    if mode == 3 {
        failure := std.time.nanosleep(std.time.timespec { seconds: 9223372036, nanoseconds: 854775807 })
        return failure.code
    }
    if mode == 4 { return std.time.sleep_ns(9223372036854775807).code }
    if mode == 5 {
        saved := std.time.timer { started_ns: 123, initialized: true }
        failure := std.time.timer_reset(saved*)
        if failure.code != 5 || saved.started_ns != 123 || !saved.initialized { return 33 }
        return 0
    }
    wall, wall_error := std.time.wall_clock()
    if wall_error.code != 0 || wall <= 0 { return 1 }
    println(std.prelude.to_string(wall))
    start, start_error := std.time.timer_start()
    if start_error.code != 0 { return 2 }
    invalid := std.time.sleep_ns(-1)
    if invalid.code != 22 { return 3 }
    invalid = std.time.sleep_ms(-1)
    if invalid.code != 22 { return 17 }
    invalid = std.time.nanosleep(std.time.timespec { seconds: 0, nanoseconds: -1 })
    if invalid.code != 22 { return 18 }
    invalid = std.time.nanosleep(std.time.timespec { seconds: 9223372036, nanoseconds: 854775808 })
    if invalid.code != 75 { return 19 }
    invalid = std.time.sleep_ms(9223372036855)
    if invalid.code != 75 { return 4 }
    invalid = std.time.nanosleep(std.time.timespec { seconds: -1, nanoseconds: 0 })
    if invalid.code != 22 { return 5 }
    invalid = std.time.nanosleep(std.time.timespec { seconds: 0, nanoseconds: 1000000000 })
    if invalid.code != 22 { return 6 }
    invalid = std.time.nanosleep(std.time.timespec { seconds: 9223372036854775807, nanoseconds: 0 })
    if invalid.code != 75 { return 7 }
    if std.time.sleep_ms(160).code != 0 { return 8 }
    if std.time.sleep_ns(20000000).code != 0 { return 9 }
    if std.time.nanosleep(std.time.timespec { seconds: 0, nanoseconds: 20000000 }).code != 0 { return 10 }
    elapsed, elapsed_error := std.time.elapsed_time(start)
    if elapsed_error.code != 0 || elapsed.nanoseconds < 200000000 { return 11 }
    println(std.prelude.to_string(elapsed.nanoseconds))
    if elapsed.milliseconds() < 200 { return 12 }
    if std.time.timer_reset(start*).code != 0 { return 13 }
    fresh, fresh_error := std.time.elapsed_time(start)
    if fresh_error.code != 0 || fresh.nanoseconds >= elapsed.nanoseconds { return 14 }
    unset := std.time.timer { started_ns: 0, initialized: false }
    ignored, unset_error := std.time.elapsed_time(unset)
    if unset_error.code != 22 { return 15 }
    if std.time.sleep_ns(0).code != 0 { return 16 }
    return 0
}
