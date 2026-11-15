package main
import ("std.kafka"; "std.tcp"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 4 { return 99 }
    ends := std.kafka.endpoint[]()
    ends = append(ends, std.kafka.endpoint { host: "127.0.0.1", port: 49092 })
    c, issue := std.kafka.consumer_new(std.kafka.consumer_config { bootstrap: ends, group_id: args[2], request_timeout_ms: 2000, connect_timeout_ms: 500, max_poll_interval_ms: 120000 })
    if issue.code != 0 { return 1 }
    topic := args[1]
    topics := string[] { topic }
    if std.kafka.consumer_subscribe(c*, topics).code != 0 { return 2 }
    start, clock_error := std.time.monotonic_clock()
    while c.state != 6 {
        problem := std.kafka.consumer_service(c*, 50)
        if c.state == 9 { println(problem.message); return 3 }
        now, now_error := std.time.monotonic_clock()
        if now - start > 45000000000 { return 4 }
    }
    mode := args[3]
    generation := c.generation_id
    if mode == "idle" {
        hold, hold_error := std.time.monotonic_clock()
        while true {
            problem := std.kafka.consumer_service(c*, 20)
            if problem.code != 0 || c.generation_id != generation { println(problem.message); return 5 }
            now, now_error := std.time.monotonic_clock()
            if now - hold > 12000000000 { break }
        }
    }
    if mode == "expired" { std.time.sleep_ms(11000) }
    if mode == "restart" {
        listener, listen_error := std.tcp.listen_ipv4("127.0.0.1", 49095, 1)
        if listen_error.code != 0 { return 6 }
        println("restart-ready")
        signal, signal_error := std.tcp.accept(listener, 90000)
        std.tcp.close(listener*)
        if signal_error.code != 0 { return 7 }
        std.tcp.close(signal*)
    }
    before, before_error := std.time.monotonic_clock()
    closed := std.kafka.consumer_close(c*, 5000)
    after, after_error := std.time.monotonic_clock()
    println("close_code=" + std.prelude.to_string(closed.code) + " native=" + std.prelude.to_string(closed.native_code) + " " + closed.message)
    if closed.code != 0 { return 8 }
    if after - before > 5500000000 { return 9 }
    if std.kafka.consumer_close(c*, 5000).code != 0 { return 10 }
    if !c.closed || len(c.decoder.input.data) != 0 || len(c.commit_snapshot) != 0 || c.outstanding_delivery_id != 0 || len(c.assigned) != 0 { return 11 }
    println("Real close and repeated cleanup: PASS")
    return 0
}
