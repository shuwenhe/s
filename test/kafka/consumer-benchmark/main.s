package main
import ("std.kafka"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 4 { return 99 }
    topic := args[1]
    group := args[2]
    endpoints := std.kafka.endpoint[]()
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 9092 })
    limit := 128
    if args[3] == "single" { limit = 1 }
    config := std.kafka.consumer_config { bootstrap: endpoints, group_id: group, max_poll_records: limit, fetch_max_bytes: 16384 }
    c, problem := std.kafka.consumer_new(config)
    if problem.code != 0 { return 1 }
    topics := string[] { topic }
    if std.kafka.consumer_subscribe(c*, topics).code != 0 { return 2 }
    started, clock_error := std.time.monotonic_clock()
    while c.state != 6 {
        issue := std.kafka.consumer_service(c*, 100)
        if issue.code != 0 && c.state == 9 { return 3 }
        now, now_error := std.time.monotonic_clock()
        if clock_error.code != 0 || now_error.code != 0 || now - started > 30000000000 { return 4 }
    }
    p, producer_error := std.kafka.producer_open("127.0.0.1", 9092, "consumer-benchmark-producer", 5000)
    if producer_error.code != 0 { return 5 }
    payload := "x"
    i := 0
    while i < 8 { payload = payload + payload; i = i + 1 }
    production_start, clock1 := std.time.monotonic_clock()
    i = 0
    while i < 128 {
        now, time_error := std.time.wall_clock()
        if time_error.code != 0 { return 6 }
        records := std.kafka.message[]()
        j := 0
        while j < 64 { records = append(records, std.kafka.message { value: std.kafka.bytes(payload), timestamp_ms: now / 1000000 }); j = j + 1 }
        result, produce_error := std.kafka.producer_publish_batch(p*, topic, 0, records, 1, 5000)
        if produce_error.code != 0 || result.offset != i * 64 { return 7 }
        if std.kafka.consumer_service(c*, 1).code != 0 { return 8 }
        i = i + 1
    }
    production_end, clock2 := std.time.monotonic_clock()
    std.kafka.producer_close(p*)
    count := 0
    polls := 0
    total_poll_ns := 0
    latency_ms := 0
    start, clock3 := std.time.monotonic_clock()
    while count < 8192 {
        before, clock4 := std.time.monotonic_clock()
        batch, poll_error := std.kafka.consumer_poll(c*, 200)
        after, clock5 := std.time.monotonic_clock()
        if poll_error.code != 0 || clock4.code != 0 || clock5.code != 0 { println(poll_error.message); return 9 }
        total_poll_ns = total_poll_ns + after - before
        polls = polls + 1
        wall, wall_error := std.time.wall_clock()
        if wall_error.code != 0 { return 10 }
        i = 0
        while i < len(batch.records) {
            record := batch.records[i].data
            if record.offset != count || record.value.data != payload { return 11 }
            latency_ms = latency_ms + wall / 1000000 - record.timestamp_ms
            count = count + 1
            if count % 1024 == 0 { println("window_records=" + std.prelude.to_string(count)) }
            i = i + 1
        }
        if len(batch.records) > 0 && std.kafka.consumer_ack(c*, batch.delivery_id).code != 0 { return 12 }
        if after - start > 60000000000 { return 13 }
    }
    end, clock6 := std.time.monotonic_clock()
    if clock1.code != 0 || clock2.code != 0 || clock3.code != 0 || clock6.code != 0 { return 14 }
    if std.kafka.consumer_commit(c*, 5000).code != 0 || std.kafka.consumer_close(c*, 3000).code != 0 { return 15 }
    println("messages=8192")
    println("payload_bytes=256")
    println("fetch_max_bytes=16384")
    println("producer_batch_records_per_second=" + std.prelude.to_string(8192000000000 / (production_end - production_start)))
    println("consumer_records_per_second=" + std.prelude.to_string(8192000000000 / (end - start)))
    println("mean_poll_latency_ns=" + std.prelude.to_string(total_poll_ns / polls))
    println("mean_end_to_end_latency_ms=" + std.prelude.to_string(latency_ms / 8192))
    println("poll_calls=" + std.prelude.to_string(polls))
    println("Consumer benchmark exact offsets/content/ACK/commit: PASS")
    return 0
}
