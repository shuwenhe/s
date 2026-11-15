package main
import ("std.kafka"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 3 { return 99 }
    topic := args[1]
    group := args[2]
    payload := "x"
    i := 0
    while i < 19 { payload = payload + payload; i = i + 1 }
    producer, producer_error := std.kafka.producer_open("127.0.0.1", 39092, "large-producer", 30000)
    if producer_error.code != 0 { return 1 }
    wall, wall_error := std.time.wall_clock()
    headers := std.kafka.header[]()
    headers = append(headers, std.kafka.header { key: "large", value: std.kafka.bytes(std.kafka.byte_string(0)) })
    message := std.kafka.message { key: std.kafka.bytes("large"), value: std.kafka.bytes(payload), timestamp_ms: wall / 1000000, headers: headers }
    published, publish_error := std.kafka.producer_publish(producer*, topic, 0, message, -1, 30000)
    std.kafka.producer_close(producer*)
    if publish_error.code != 0 || published.offset != 0 { return 2 }
    endpoints := std.kafka.endpoint[]()
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 39092 })
    config := std.kafka.consumer_config { bootstrap: endpoints, group_id: group, request_timeout_ms: 5000, max_poll_records: 1, fetch_max_bytes: 786432 }
    c, problem := std.kafka.consumer_new(config)
    if problem.code != 0 { return 3 }
    topics := string[] { topic }
    if std.kafka.consumer_subscribe(c*, topics).code != 0 { return 4 }
    start, clock_error := std.time.monotonic_clock()
    while c.state != 6 {
        issue := std.kafka.consumer_service(c*, 100)
        if issue.code != 0 && c.state == 9 { println(issue.message); return 5 }
        now, time_error := std.time.monotonic_clock()
        if time_error.code != 0 || now - start > 45000000000 { return 6 }
    }
    generation := c.generation_id
    before, before_error := std.time.monotonic_clock()
    max_poll_ns := 0
    polls := 0
    while true {
        begin, begin_error := std.time.monotonic_clock()
        batch, issue := std.kafka.consumer_poll(c*, 200)
        end, end_error := std.time.monotonic_clock()
        if issue.code != 0 { println(issue.message); return 7 }
        polls = polls + 1
        if end - begin > max_poll_ns { max_poll_ns = end - begin }
        if c.generation_id != generation { return 8 }
        if len(batch.records) > 0 {
            record := batch.records[0].data
            if record.offset != 0 || record.value.data != payload || record.key.data != "large" || record.timestamp_ms != message.timestamp_ms || len(record.headers) != 1 || record.headers[0].key != "large" || record.headers[0].value.data != std.kafka.byte_string(0) { return 9 }
            if end - before > 4000000000 && c.last_heartbeat_ns <= before { return 10 }
            if max_poll_ns > 500000000 { println("excess_poll_ns=" + std.prelude.to_string(max_poll_ns)); return 15 }
            if std.kafka.consumer_ack(c*, batch.delivery_id).code != 0 || std.kafka.consumer_commit(c*, 3000).code != 0 { return 11 }
            if c.assigned[0].committed_offset != 1 || std.kafka.consumer_close(c*, 3000).code != 0 { return 12 }
            println("bytes=524288")
            println("request_timeout_ms=5000")
            println("fetch_max_bytes=786432")
            println("fetch_elapsed_ns=" + std.prelude.to_string(end - before))
            println("max_poll_call_ns=" + std.prelude.to_string(max_poll_ns))
            println("poll_calls=" + std.prelude.to_string(polls))
            println("Real large-record content/CRC/heartbeat/generation/ACK/commit: PASS")
            return 0
        }
        if end - before > 60000000000 { return 13 }
    }
    return 14
}
