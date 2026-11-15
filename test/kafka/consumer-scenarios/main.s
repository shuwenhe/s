package main
import ("std.kafka"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func open_client(string group, string[] topics, int initial_offset) (std.kafka.consumer,std.kafka.error) {
    endpoints := std.kafka.endpoint[]()
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 9092 })
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 19093 })
    config := std.kafka.consumer_config { bootstrap: endpoints, group_id: group, max_poll_records: 2, initial_offset: initial_offset }
    c, problem := std.kafka.consumer_new(config)
    if problem.code != 0 { return c, problem }
    issue := std.kafka.consumer_subscribe(c*, topics)
    return c, issue
}
func produce(string topic, int partition_id, int port, string value) int {
    // Resolve the current leader: a real restart may elect either replica.
    link, link_error := std.kafka.consumer_link_open("127.0.0.1", port, "s-scenario-metadata", 1000)
    if link_error.code != 0 { return 1 }
    request, build_error := std.kafka.consumer_build_metadata("s-scenario-metadata", link.connection.correlation_id, string[] { topic })
    if build_error.code != 0 { std.kafka.consumer_link_close(link*); return 1 }
    exchange_error := std.kafka.consumer_exchange_begin(link*, request, 1000)
    if exchange_error.code != 0 { std.kafka.consumer_link_close(link*); return 1 }
    while link.state != 4 && link.problem.code == 0 { std.kafka.consumer_exchange_step(link*, 1) }
    if link.problem.code != 0 { std.kafka.consumer_link_close(link*); return 1 }
    metadata, metadata_error := std.kafka.consumer_parse_metadata(link.body)
    std.kafka.consumer_link_close(link*)
    if metadata_error.code != 0 { return 1 }
    leader := -1
    i := 0
    while i < len(metadata.partitions) {
        part := metadata.partitions[i]
        if part.topic == topic && part.partition_id == partition_id { leader = part.leader_id }
        i = i + 1
    }
    target, endpoint_error := std.kafka.consumer_metadata_endpoint(metadata, leader)
    if endpoint_error.code != 0 { return 1 }
    p, problem := std.kafka.producer_open(target.host, target.port, "s-scenario-producer", 3000)
    if problem.code != 0 { return 1 }
    now, clock_error := std.time.wall_clock()
    if clock_error.code != 0 { return 2 }
    record := std.kafka.message { key: std.kafka.bytes("scenario"), value: std.kafka.bytes(value), timestamp_ms: now / 1000000 }
    result, issue := std.kafka.producer_publish(p*, topic, partition_id, record, -1, 3000)
    std.kafka.producer_close(p*)
    if issue.code != 0 { return 3 }
    return 0
}
func describe(std.kafka.consumer* c) int {
    link := c.group_link
    request, problem := std.kafka.consumer_build_describe(c.config.client_id, link.connection.correlation_id, c.config.group_id)
    if problem.code != 0 { return 1 }
    issue := std.kafka.consumer_exchange_begin(link*, request, 1000)
    if issue.code != 0 { return 2 }
    while link.state != 4 && link.problem.code == 0 { std.kafka.consumer_exchange_step(link*, 1) }
    c.group_link = link
    if link.problem.code != 0 { return 3 }
    result, parse_error := std.kafka.consumer_parse_describe(link.body, c.config.group_id)
    if parse_error.code != 0 || result.state != "Stable" || result.member_count != 1 || result.protocol_name != "range" { return 4 }
    return 0
}
func main() int {
    args := host_args()
    if len(args) != 5 { return 99 }
    mode := args[1]
    group := args[2]
    topic_a := args[3]
    topic_b := args[4]
    topics := string[] { topic_a }
    if mode == "multi" { topics = append(topics, topic_b) }
    initial := 0
    if mode == "latest" { initial = 1 }
    c, problem := open_client(group, topics, initial)
    if problem.code != 0 { return 1 }
    // Initial native production precedes group consumption.
    if mode == "multi" {
        if produce(topic_a, 0, 9092, "a0") != 0 || produce(topic_a, 1, 9092, "a1") != 0 || produce(topic_b, 0, 19093, "b0") != 0 || produce(topic_b, 1, 19093, "b1") != 0 { return 3 }
    } else if mode == "latest" {
        if produce(topic_a, 0, 9092, "old") != 0 { return 4 }
    } else {
        if produce(topic_a, 0, 9092, "before-restart") != 0 { return 4 }
    }
    start, clock_error := std.time.monotonic_clock()
    if clock_error.code != 0 { return 5 }
    seen := int[] { 0, 0, 0, 0 }
    total := 0
    recovery_announced := false
    produced_after := false
    events := 0
    while true {
        batch, issue := std.kafka.consumer_poll(c*, 200)
        if issue.code != 0 {
            events = events + 1
            println("recovery-event=" + std.prelude.to_string(issue.code) + ":" + std.prelude.to_string(issue.native_code))
            if c.state == 9 { println(issue.message); println(std.prelude.to_string(issue.native_code)); return 6 }
        }
        if len(batch.records) > 0 {
            i := 0
            while i < len(batch.records) {
                item := batch.records[i]
                record := item.data
                if mode == "multi" {
                    index := record.partition
                    if item.topic == topic_b { index = index + 2 }
                    if index < 0 || index > 3 || seen[index] != 0 || record.offset != 0 || record.key.data != "scenario" { return 7 }
                    seen[index] = seen[index] + 1
                } else if mode == "latest" {
                    if record.offset != 1 || record.value.data != "new" { return 8 }
                } else {
                    if record.offset != total { return 8 }
                    if total == 0 && record.value.data != "before-restart" { return 9 }
                    if total == 1 && record.value.data != "after-restart" { return 10 }
                }
                total = total + 1
                i = i + 1
            }
            if mode == "processing" {
                generation := c.generation_id
                processing_start, processing_clock_error := std.time.monotonic_clock()
                while true {
                    service_error := std.kafka.consumer_service(c*, 100)
                    if service_error.code != 0 || c.generation_id != generation || c.outstanding_delivery_id != batch.delivery_id { return 19 }
                    candidates := std.kafka.consumer_commit_candidates(c*)
                    if len(candidates) != 0 { return 20 }
                    processing_now, processing_now_error := std.time.monotonic_clock()
                    if processing_now - processing_start > 14000000000 { break }
                }
            }
            if std.kafka.consumer_ack(c*, batch.delivery_id).code != 0 { return 11 }
            commit_error := std.kafka.consumer_commit(c*, 3000)
            if commit_error.code != 0 { println(commit_error.message); return 12 }
        }
        if mode == "processing" && total == 1 { break }
        if mode == "multi" && total == 4 {
            if len(c.assigned) != 4 || describe(c*) != 0 { return 13 }
            i := 0
            while i < len(c.assigned) { if c.assigned[i].committed_offset != 1 { return 14 } i = i + 1 }
            break
        }
        if mode == "latest" && c.state == 6 && !produced_after {
            if produce(topic_a, 0, 9092, "new") != 0 { return 18 }
            produced_after = true
        }
        if mode == "latest" && total == 1 { break }
        if mode == "recovery" && total == 1 && !recovery_announced {
            println("recovery-ready")
            recovery_announced = true
        }
        if mode == "recovery" && recovery_announced && events > 0 && !produced_after {
            if produce(topic_a, 0, 9092, "after-restart") == 0 { produced_after = true }
        }
        if mode == "recovery" && total == 2 {
            if !produced_after || events == 0 || c.assigned[0].committed_offset != 2 { return 15 }
            break
        }
        now, now_error := std.time.monotonic_clock()
        if now_error.code != 0 || now - start > 90000000000 { return 16 }
    }
    if std.kafka.consumer_close(c*, 3000).code != 0 { return 17 }
    println("REAL Consumer scenario " + mode + ": PASS")
    return 0
}
