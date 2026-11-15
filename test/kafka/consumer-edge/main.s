package main
import ("std.kafka"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func now() int { value, issue := std.time.monotonic_clock(); return value }
func open_client(string group, string topic, string name) (std.kafka.consumer,std.kafka.error) {
    endpoints := std.kafka.endpoint[]()
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 29092 })
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 29093 })
    config := std.kafka.consumer_config { bootstrap: endpoints, group_id: group, client_id: name, max_poll_records: 1 }
    c, issue := std.kafka.consumer_new(config)
    if issue.code != 0 { return c, issue }
    topics := string[] { topic }
    problem := std.kafka.consumer_subscribe(c*, topics)
    return c, problem
}
func produce_at(string topic, int port, string value) int {
    link, issue := std.kafka.consumer_link_open("127.0.0.1", port, "edge-meta", 1000)
    if issue.code != 0 { return 1 }
    topics := string[] { topic }
    request, build_error := std.kafka.consumer_build_metadata("edge-meta", link.connection.correlation_id, topics)
    if build_error.code != 0 { std.kafka.consumer_link_close(link*); return 2 }
    begin_error := std.kafka.consumer_exchange_begin(link*, request, 1000)
    if begin_error.code != 0 { std.kafka.consumer_link_close(link*); return 3 }
    while link.state != 4 && link.problem.code == 0 { std.kafka.consumer_exchange_step(link*, 1) }
    if link.problem.code != 0 { std.kafka.consumer_link_close(link*); return 4 }
    meta, metadata_error := std.kafka.consumer_parse_metadata(link.body)
    std.kafka.consumer_link_close(link*)
    if metadata_error.code != 0 || len(meta.partitions) == 0 { return 5 }
    target, target_error := std.kafka.consumer_metadata_endpoint(meta, meta.partitions[0].leader_id)
    if target_error.code != 0 { return 6 }
    p, producer_error := std.kafka.producer_open(target.host, target.port, "edge-producer", 1000)
    if producer_error.code != 0 { return 7 }
    timestamp, clock_error := std.time.wall_clock()
    record := std.kafka.message { value: std.kafka.bytes(value), timestamp_ms: timestamp / 1000000 }
    result, publish_error := std.kafka.producer_publish(p*, topic, 0, record, -1, 1000)
    std.kafka.producer_close(p*)
    if publish_error.code != 0 { return 8 }
    return 0
}
func produce(string topic, string value) int {
    first := produce_at(topic, 29092, value)
    if first == 0 { return 0 }
    return produce_at(topic, 29093, value)
}
func stable(std.kafka.consumer* c, int partitions) int {
    deadline := now() + 45000000000
    while now() < deadline {
        issue := std.kafka.consumer_service(c*, 100)
        if issue.code != 0 && c.state == 9 { return 1 }
        if c.state == 6 && len(c.assigned) == partitions { return 0 }
    }
    return 2
}
func next_batch(std.kafka.consumer* c) (std.kafka.consumer_batch,int) {
    deadline := now() + 45000000000
    while now() < deadline {
        batch, issue := std.kafka.consumer_poll(c*, 200)
        if issue.code != 0 && c.state == 9 { return batch, 1 }
        if len(batch.records) != 0 { return batch, 0 }
    }
    return std.kafka.consumer_batch {}, 2
}
func crash_case(string mode, string group, string topic) int {
    if mode == "crash-uncommitted" || mode == "crash-committed" {
        if produce(topic, "first") != 0 || produce(topic, "second") != 0 { return 1 }
    }
    c, problem := open_client(group, topic, "edge-crash")
    if problem.code != 0 { return 2 }
    batch, poll_error := next_batch(c*)
    if poll_error != 0 { return 3 }
    expected := 0
    if mode == "resume-committed" { expected = 1 }
    if batch.records[0].data.offset != expected { return 4 }
    if std.kafka.consumer_ack(c*, batch.delivery_id).code != 0 { return 5 }
    if mode != "crash-uncommitted" {
        if std.kafka.consumer_commit(c*, 3000).code != 0 { return 6 }
    }
    if mode == "crash-uncommitted" || mode == "crash-committed" {
        println("crash-ready")
        while true { std.kafka.consumer_service(c*, 100) }
    }
    if std.kafka.consumer_close(c*, 3000).code != 0 { return 7 }
    println("Real SIGKILL crash offset recovery: PASS")
    return 0
}
func stale_commit(std.kafka.consumer* c, std.kafka.topic_partition[] snapshot, int old_generation, string old_member) int {
    link, issue := std.kafka.consumer_link_open(c.coordinator.host, c.coordinator.port, "edge-stale", 1000)
    if issue.code != 0 { return 1 }
    request, build_error := std.kafka.consumer_build_offset_commit("edge-stale", link.connection.correlation_id, c.config.group_id, old_member, old_generation, snapshot)
    if build_error.code != 0 { return 2 }
    begin_error := std.kafka.consumer_exchange_begin(link*, request, 1000)
    if begin_error.code != 0 { return 3 }
    while link.state != 4 && link.problem.code == 0 { std.kafka.consumer_exchange_step(link*, 1) }
    results, parse_error := std.kafka.consumer_parse_offsets(link.body, snapshot, 8)
    std.kafka.consumer_link_close(link*)
    if parse_error.code != std.kafka.error_broker || (parse_error.native_code != 22 && parse_error.native_code != 25) { return 4 }
    return 0
}
func rebalance_case(string group, string topic) int {
    if produce(topic, "replay") != 0 || produce(topic, "next") != 0 { return 1 }
    first, first_error := open_client(group, topic, "edge-first")
    if first_error.code != 0 || stable(first*, 4) != 0 { return 2 }
    processed, processed_error := next_batch(first*)
    if processed_error != 0 || std.kafka.consumer_ack(first*, processed.delivery_id).code != 0 { return 3 }
    snapshot := std.kafka.consumer_commit_candidates(first*)
    old_generation := first.generation_id
    old_member := first.member_id
    outstanding, outstanding_error := next_batch(first*)
    if outstanding_error != 0 { return 4 }
    old_epoch := first.assignment_epoch
    second, second_error := open_client(group, topic, "edge-second")
    if second_error.code != 0 { return 5 }
    deadline := now() + 45000000000
    joined := false
    while now() < deadline {
        one := std.kafka.consumer_service(first*, 100)
        two := std.kafka.consumer_service(second*, 100)
        if first.state == 9 || second.state == 9 { return 6 }
        if first.state == 6 && second.state == 6 && len(first.assigned) == 2 && len(second.assigned) == 2 { joined = true; break }
    }
    if !joined || first.assignment_epoch <= old_epoch { return 7 }
    stale := std.kafka.consumer_ack(first*, outstanding.delivery_id)
    if stale.code == 0 { return 8 }
    if stale_commit(first*, snapshot, old_generation, old_member) != 0 { return 9 }
    if std.kafka.consumer_close(first*, 3000).code != 0 { return 10 }
    if stable(second*, 4) != 0 { return 11 }
    println("Real survivor receives all revoked peer partitions: PASS")
    delayed, delayed_error := next_batch(second*)
    if delayed_error != 0 { return 12 }
    token := delayed.delivery_id
    std.time.sleep_ms(11000)
    session_error := std.kafka.consumer_service(second*, 100)
    if session_error.code != std.kafka.error_rebalance || second.outstanding_delivery_id != 0 { return 13 }
    if std.kafka.consumer_ack(second*, token).code == 0 { return 14 }
    if stable(second*, 4) != 0 { return 15 }
    replayed, replay_error := next_batch(second*)
    if replay_error != 0 || replayed.records[0].data.offset != delayed.records[0].data.offset { return 16 }
    if std.kafka.consumer_ack(second*, replayed.delivery_id).code != 0 || std.kafka.consumer_commit(second*, 3000).code != 0 { return 17 }
    if std.kafka.consumer_close(second*, 3000).code != 0 { return 18 }
    println("Real rebalance/session stale ACK and uncommitted replay: PASS")
    return 0
}
func error_case(string mode, string group, string topic) int {
    if mode == "range-error" && produce(topic, "record") != 0 { return 1 }
    c, problem := open_client(group, topic, "edge-error")
    if problem.code != 0 { return 2 }
    if mode == "unknown" {
        deadline := now() + 15000000000
        observed := false
        while now() < deadline {
            issue := std.kafka.consumer_service(c*, 200)
            if issue.code == std.kafka.error_broker && issue.native_code == 3 { observed = true; break }
            if c.state == 9 { println(issue.message); return 3 }
        }
        if !observed { return 4 }
    } else {
        if stable(c*, 1) != 0 { return 5 }
        if std.kafka.consumer_seek(c*, topic, 0, 999999).code != 0 { return 6 }
        deadline := now() + 15000000000
        observed := false
        while now() < deadline {
            batch, issue := std.kafka.consumer_poll(c*, 200)
            if issue.code == std.kafka.error_broker && issue.native_code == 1 && len(batch.records) == 0 { observed = true; break }
        }
        if !observed || c.state != 9 { return 7 }
        candidates := std.kafka.consumer_commit_candidates(c*)
        if len(candidates) != 0 { return 8 }
        if std.kafka.consumer_seek(c*, topic, 0, 0).code != 0 { return 9 }
        recovered, recovery_error := next_batch(c*)
        if recovery_error != 0 || recovered.records[0].data.offset != 0 { return 10 }
        if std.kafka.consumer_ack(c*, recovered.delivery_id).code != 0 || std.kafka.consumer_commit(c*, 3000).code != 0 { return 11 }
    }
    if std.kafka.consumer_close(c*, 3000).code != 0 { return 12 }
    println("Real unknown-topic/out-of-range error and explicit recovery: PASS")
    return 0
}
func failover_case(string group, string topic) int {
    if produce(topic, "before") != 0 { return 1 }
    c, problem := open_client(group, topic, "edge-failover")
    if problem.code != 0 { return 2 }
    before, before_error := next_batch(c*)
    if before_error != 0 || before.records[0].data.offset != 0 { return 3 }
    if std.kafka.consumer_ack(c*, before.delivery_id).code != 0 || std.kafka.consumer_commit(c*, 3000).code != 0 { return 4 }
    println("coordinator-port=" + std.prelude.to_string(c.coordinator.port))
    println("failover-ready")
    events := 0
    produced := false
    deadline := now() + 90000000000
    while now() < deadline {
        batch, issue := std.kafka.consumer_poll(c*, 200)
        if issue.code != 0 {
            events = events + 1
            println("failover-event=" + issue.message)
            if c.state == 9 { return 5 }
        }
        if events > 0 && !produced { if produce(topic, "after") == 0 { produced = true } }
        if len(batch.records) > 0 {
            if batch.records[0].data.offset != 1 || batch.records[0].data.value.data != "after" || !produced { return 6 }
            if std.kafka.consumer_ack(c*, batch.delivery_id).code != 0 { return 7 }
            commit_error := std.kafka.consumer_commit(c*, 3000)
            if commit_error.code == 0 {
                if c.assigned[0].committed_offset != 2 { return 8 }
                if std.kafka.consumer_close(c*, 3000).code != 0 { return 9 }
                println("Real live single-broker leader/coordinator failover: PASS")
                return 0
            }
            if c.state == 9 { return 10 }
        }
    }
    return 11
}
func main() int {
    args := host_args()
    if len(args) != 4 { return 99 }
    if args[1] == "rebalance" { return rebalance_case(args[2], args[3]) }
    if args[1] == "unknown" || args[1] == "range-error" { return error_case(args[1], args[2], args[3]) }
    if args[1] == "failover" { return failover_case(args[2], args[3]) }
    return crash_case(args[1], args[2], args[3])
}
