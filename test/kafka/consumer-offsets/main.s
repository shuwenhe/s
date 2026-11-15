package main
import ("std.kafka"; "std.time")
extern "intrinsic" func host_args() string[]
func open_consumer(string group, string topic, bool auto_commit) (std.kafka.consumer,std.kafka.error) {
    endpoints := std.kafka.endpoint[]()
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 9092 })
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 19093 })
    cfg := std.kafka.consumer_config { bootstrap: endpoints, group_id: group, auto_commit: auto_commit, auto_commit_interval_ms: 1000, max_poll_records: 1 }
    c, problem := std.kafka.consumer_new(cfg)
    if problem.code != 0 { return c, problem }
    topics := string[] { topic }
    issue := std.kafka.consumer_subscribe(c*, topics)
    return c, issue
}
func receive(std.kafka.consumer* c) (std.kafka.consumer_batch,std.kafka.error) {
    started, clock_error := std.time.monotonic_clock()
    while true {
        batch, problem := std.kafka.consumer_poll(c*, 200)
        if problem.code != 0 && c.state == 9 { return batch, problem }
        if len(batch.records) > 0 { return batch, problem }
        now, now_error := std.time.monotonic_clock()
        if clock_error.code != 0 || now_error.code != 0 || now - started > 30000000000 { return batch, std.kafka.failure(std.kafka.error_timeout, "receive deadline") }
    }
    return std.kafka.consumer_batch {}, std.kafka.failure(std.kafka.error_timeout, "receive stopped")
}
func main() int {
    args := host_args()
    if len(args) != 3 { return 99 }
    group := args[1]
    topic := args[2]
    producer, open_error := std.kafka.producer_open("127.0.0.1", 9092, "s-offset-producer", 5000)
    if open_error.code != 0 { return 1 }
    now, clock_error := std.time.wall_clock()
    if clock_error.code != 0 { return 2 }
    records := std.kafka.message[]()
    records = append(records, std.kafka.message { key: std.kafka.bytes("k"), value: std.kafka.bytes("one"), timestamp_ms: now / 1000000 })
    records = append(records, std.kafka.message { value: std.kafka.bytes("two"), timestamp_ms: now / 1000000 })
    records = append(records, std.kafka.message { value: std.kafka.bytes("three"), timestamp_ms: now / 1000000 })
    result, produce_error := std.kafka.producer_publish_batch(producer*, topic, 0, records, -1, 5000)
    if produce_error.code != 0 || result.offset != 0 { return 3 }
    std.kafka.producer_close(producer*)
    c, problem := open_consumer(group, topic, false)
    if problem.code != 0 { return 4 }
    first, first_error := receive(c*)
    if first_error.code != 0 || first.records[0].data.offset != 0 || first.records[0].data.value.data != "one" { return 5 }
    // Manual commit before ACK is a no-op; it cannot bless an unprocessed record.
    if std.kafka.consumer_commit(c*, 3000).code != 0 { return 6 }
    if c.assigned[0].committed_offset != -1 { return 7 }
    if std.kafka.consumer_ack(c*, first.delivery_id).code != 0 { return 8 }
    if std.kafka.consumer_commit(c*, 5000).code != 0 { return 9 }
    if c.assigned[0].committed_offset != 1 { return 10 }
    if std.kafka.consumer_close(c*, 3000).code != 0 { return 11 }
    restarted, restart_error := open_consumer(group, topic, false)
    if restart_error.code != 0 { return 12 }
    second, second_error := receive(restarted*)
    if second_error.code != 0 || second.records[0].data.offset != 1 || second.records[0].data.value.data != "two" { return 13 }
    if std.kafka.consumer_close(restarted*, 3000).code != 0 { return 14 }
    replay, replay_error := open_consumer(group, topic, true)
    if replay_error.code != 0 { return 15 }
    again, again_error := receive(replay*)
    if again_error.code != 0 || again.records[0].data.offset != 1 { return 16 }
    // Service while unacknowledged must not auto-commit the returned record.
    if std.kafka.consumer_service(replay*, 1500).code != 0 { return 17 }
    if replay.assigned[0].committed_offset != 1 { return 18 }
    if std.kafka.consumer_ack(replay*, again.delivery_id).code != 0 { return 19 }
    if std.kafka.consumer_service(replay*, 1500).code != 0 || replay.assigned[0].committed_offset != 2 { return 20 }
    third, third_error := receive(replay*)
    if third_error.code != 0 || third.records[0].data.offset != 2 { return 21 }
    old_id := third.delivery_id
    if std.kafka.consumer_seek(replay*, topic, 0, 0).code != 0 { return 22 }
    if std.kafka.consumer_ack(replay*, old_id).code == 0 { return 23 }
    if std.kafka.consumer_close(replay*, 3000).code != 0 { return 24 }
    println("REAL explicit ACK/manual commit/restart/unacked replay/auto commit/service gate/seek fencing: PASS")
    return 0
}
