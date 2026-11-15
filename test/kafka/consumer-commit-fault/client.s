package main
import ("std.kafka"; "std.time")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 2 { return 99 }
    mode := args[1]
    endpoints := std.kafka.endpoint[]()
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 19096 })
    config := std.kafka.consumer_config { bootstrap: endpoints, group_id: "commit-group", request_timeout_ms: 200, connect_timeout_ms: 100 }
    c, problem := std.kafka.consumer_new(config)
    if problem.code != 0 { return 1 }
    c.state = 6
    c.member_id = "member"
    c.generation_id = 7
    c.assignment_epoch = 3
    c.coordinator = endpoints[0]
    now, clock_error := std.time.monotonic_clock()
    c.last_poll_ns = now
    c.last_heartbeat_ns = now
    c.next_heartbeat_ns = now + 3000000000
    c.next_metadata_ns = now + 30000000000
    c.assigned = append(c.assigned, std.kafka.topic_partition { topic: "topic", partition_id: 0, offset: 99, processed_offset: 45, committed_offset: 44, processed_valid: true })
    if mode == "partial" { c.assigned = append(c.assigned, std.kafka.topic_partition { topic: "topic", partition_id: 1, offset: 99, processed_offset: 20, committed_offset: 19, processed_valid: true }) }
    issue := std.kafka.consumer_commit(c*, 1500)
    if issue.code == 0 || c.assigned[0].processed_offset != 45 { return 2 }
    if mode == "auth" {
        if issue.native_code != 30 || c.state != 9 || c.assigned[0].committed_offset != 44 { return 3 }
    } else {
        if c.state != 6 { return 4 }
        expected := 44
        if mode == "partial" { expected = 45 }
        if c.assigned[0].committed_offset != expected { return 5 }
        candidates := std.kafka.consumer_commit_candidates(c*)
        if mode == "partial" && (len(candidates) != 1 || candidates[0].partition_id != 1 || candidates[0].offset != 20) { return 6 }
        if mode != "partial" && (len(candidates) != 1 || candidates[0].offset != 45) { return 7 }
        retried := std.kafka.consumer_commit(c*, 1500)
        if retried.code != 0 || c.assigned[0].committed_offset != 45 { return 8 }
        if mode == "partial" && c.assigned[1].committed_offset != 20 { return 9 }
    }
    // This fixture has no real membership; close only its owned transport.
    c.member_id = ""
    if std.kafka.consumer_close(c*, 100).code != 0 { return 10 }
    println("Native OffsetCommit lost-response/timeout/partial/authorization fixture: PASS")
    return 0
}
