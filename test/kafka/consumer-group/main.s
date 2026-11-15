package main
import ("std.kafka"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 5 { return 99 }
    bootstrap := std.kafka.endpoint[]()
    bootstrap = append(bootstrap, std.kafka.endpoint { host: "127.0.0.1", port: 9092 })
    bootstrap = append(bootstrap, std.kafka.endpoint { host: "127.0.0.1", port: 19093 })
    config := std.kafka.consumer_config { bootstrap: bootstrap, group_id: args[1], client_id: args[2] }
    if args[4] == "maxpoll" { config.max_poll_interval_ms = 6000 }
    c, problem := std.kafka.consumer_new(config)
    if problem.code != 0 { println(problem.message); return 1 }
    topic := args[3]
    topics := string[] { topic }
    if std.kafka.consumer_subscribe(c*, topics).code != 0 { return 2 }
    start, clock_error := std.time.monotonic_clock()
    if clock_error.code != 0 { return 3 }
    previous_generation := -1
    stable_since := 0
    lapsed := false
    session_rejoined := false
    while true {
        issue := std.kafka.consumer_service(c*, 100)
        if issue.code != 0 {
            println("event=" + issue.message)
            println(std.prelude.to_string(issue.native_code))
            if c.state == 9 { return 4 }
            if args[4] == "maxpoll" && issue.code == std.kafka.error_poll_interval {
                if c.state != 10 || c.generation_id != -1 || len(c.assigned) != 0 { return 9 }
                std.kafka.consumer_close(c*, 1000)
                println("Consumer max-poll enforcement: PASS")
                return 0
            }
            if args[4] == "lapse" && issue.code == std.kafka.error_rebalance { session_rejoined = true }
        }
        now, now_error := std.time.monotonic_clock()
        if now_error.code != 0 || now - start > 65000000000 { return 5 }
        if c.state == 6 {
            if args[4] == "lapse" && !lapsed {
                lapsed = true
                std.time.sleep_ms(11000)
                continue
            }
            if c.generation_id != previous_generation {
                if args[4] == "heartbeat" && previous_generation >= 0 { return 10 }
                previous_generation = c.generation_id
                stable_since = now
                println("member=" + c.member_id + " generation=" + std.prelude.to_string(c.generation_id) + " count=" + std.prelude.to_string(len(c.assigned)))
            }
            if args[4] == "growth" && len(c.assigned) == 2 { break }
            hold := 5000000000
            if args[4] == "growth" { hold = 70000000000 }
            if args[4] == "heartbeat" { hold = 14000000000 }
            if args[4] == "maxpoll" { hold = 20000000000 }
            if now - stable_since > hold {
                i := 0
                while i < len(c.assigned) {
                    p := c.assigned[i]
                    println("assignment=" + p.topic + ":" + std.prelude.to_string(p.partition_id))
                    i = i + 1
                }
                if args[4] == "single" && len(c.assigned) != 4 { return 6 }
                if args[4] == "pair" && len(c.assigned) != 2 { return 7 }
                if args[4] == "lapse" && !session_rejoined { return 11 }
                break
            }
        }
    }
    if args[4] == "reconnectclose" {
        lost := c.group_link
        std.kafka.consumer_link_close(lost*)
        c.group_link = lost
    }
    if std.kafka.consumer_close(c*, 1000).code != 0 { return 8 }
    if args[4] == "reconnectclose" { println("Graceful LeaveGroup reconnect: PASS") }
    println("Classic Range real group membership: PASS")
    return 0
}
