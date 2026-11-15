package main
import ("std.kafka"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
extern "intrinsic" func __host_byte_at(string value, int index) int
func number(string value) int {
    if value == "1024" { return 1024 }
    if value == "16384" { return 16384 }
    if value == "65536" { return 65536 }
    if value == "262144" { return 262144 }
    if value == "524288" { return 524288 }
    if value == "1048576" { return 1048576 }
    if value == "1800" { return 1800 }
    if value == "16" { return 16 }
    return 0
}
func checkpoint(string phase, int count) {
    println("phase=" + phase + " count=" + std.prelude.to_string(count))
    std.time.sleep_ms(100)
    return
}
func main() int {
    args := host_args()
    if len(args) != 5 { return 99 }
    topic := args[1]
    size := number(args[2])
    seconds := number(args[3])
    rounds := number(args[4])
    checkpoint("initial", 0)
    endpoints := std.kafka.endpoint[]()
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 39092 })
    cfg := std.kafka.consumer_config { bootstrap: endpoints, group_id: topic + "-group", max_poll_records: 1, request_timeout_ms: 30000, max_poll_interval_ms: 60000 }
    c, problem := std.kafka.consumer_new(cfg)
    if problem.code != 0 { return 1 }
    topics := string[] { topic }
    if std.kafka.consumer_subscribe(c*, topics).code != 0 { return 2 }
    start, clock_error := std.time.monotonic_clock()
    if clock_error.code != 0 { return 3 }
    count := 0
    rebalanced := false
    while true {
        batch, issue := std.kafka.consumer_poll(c*, 200)
        if issue.code != 0 {
            println("error=" + std.prelude.to_string(issue.code) + " native=" + std.prelude.to_string(issue.native_code) + " " + issue.message)
            if c.state == 9 { checkpoint("terminal", count); std.kafka.consumer_close(c*, 1000); checkpoint("cleanup", count); return 4 }
        }
        if len(batch.records) > 0 {
            record := batch.records[0].data
            if len(record.value.data) != size || __host_byte_at(record.value.data, 0) != 120 || __host_byte_at(record.value.data, size - 1) != 120 { return 5 }
            if count < 3 || count % 60 == 0 { checkpoint("delivered", count) }
            if std.kafka.consumer_ack(c*, batch.delivery_id).code != 0 { return 6 }
            if count < 3 || count % 60 == 0 { checkpoint("ack", count) }
            if std.kafka.consumer_commit(c*, 5000).code != 0 { return 7 }
            if count < 3 || count % 60 == 0 { checkpoint("commit", count) }
            count = count + 1
            now, time_error := std.time.monotonic_clock()
            if time_error.code != 0 { return 8 }
            if seconds == 0 && count >= rounds { break }
            if seconds > 0 && now - start >= seconds * 1000000000 { break }
            if !rebalanced && count == 3 {
                checkpoint("before-rebalance", count)
                std.time.sleep_ms(11000)
                service_error := std.kafka.consumer_service(c*, 10)
                if service_error.code == 0 { return 9 }
                checkpoint("revoked", count)
                rebalanced = true
            }
            if c.state == 6 {
                if std.kafka.consumer_seek(c*, topic, 0, 0).code != 0 { return 10 }
            }
            if seconds > 0 { std.time.sleep_ms(750) }
        } else {
            now, time_error := std.time.monotonic_clock()
            if time_error.code != 0 || now - start > (seconds + 90) * 1000000000 { return 11 }
            // After session-loss rejoin, committed offset is 1; explicitly replay.
            if rebalanced && c.state == 6 && c.assigned[0].offset == 1 {
                if std.kafka.consumer_seek(c*, topic, 0, 0).code != 0 { return 12 }
                checkpoint("rejoined", count)
            }
        }
    }
    checkpoint("before-cleanup", count)
    close_issue := std.kafka.consumer_close(c*, 3000)
    println("close_code=" + std.prelude.to_string(close_issue.code) + " native=" + std.prelude.to_string(close_issue.native_code) + " " + close_issue.message)
    if close_issue.code != 0 { return 13 }
    checkpoint("closed", count)
    c = std.kafka.consumer {}
    checkpoint("cleanup", count)
    std.time.sleep_ms(2000)
    checkpoint("idle-after-cleanup", count)
    return 0
}
