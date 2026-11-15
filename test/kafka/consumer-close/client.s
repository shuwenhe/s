package main
import ("std.kafka"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func main() int {
    args := host_args()
    if len(args) != 2 { return 99 }
    mode := args[1]
    endpoints := std.kafka.endpoint[]()
    port := 19092
    if mode == "coordinator-loss" { port = 19093 }
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: port })
    config := std.kafka.consumer_config { bootstrap: endpoints, group_id: "close-group", connect_timeout_ms: 100, request_timeout_ms: 500 }
    c, problem := std.kafka.consumer_new(config)
    if problem.code != 0 { return 1 }
    c.state = 6
    c.member_id = "close-member"
    c.generation_id = 1
    c.assignment_epoch = 1
    c.coordinator = std.kafka.endpoint { host: "127.0.0.1", port: 19092 }
    now, clock_error := std.time.monotonic_clock()
    c.last_heartbeat_ns = now
    c.last_poll_ns = now
    if mode != "unavailable" && mode != "cleanup" {
        link, open_error := std.kafka.consumer_link_open("127.0.0.1", 19092, "close-client", 1000)
        if open_error.code != 0 { println(open_error.message); return 2 }
        c.group_link = link
        std.time.sleep_ms(150)
    }
    if mode == "cleanup" { c.member_id = "" }
    c.decoder = std.kafka.consumer_decoder_new("retained-decoder", 0, 0, false)
    c.commit_snapshot = append(c.commit_snapshot, std.kafka.topic_partition { topic: "topic", partition_id: 0 })
    c.assigned = c.commit_snapshot
    c.queue = append(c.queue, std.kafka.message { value: std.kafka.bytes("retained-queue") })
    c.outstanding_delivery_id = 9
    c.outstanding_epoch = 1
    c.outstanding_end_offset = 10
    start, start_error := std.time.monotonic_clock()
    issue := std.kafka.consumer_close(c*, 600)
    end, end_error := std.time.monotonic_clock()
    println("close_code=" + std.prelude.to_string(issue.code) + " native=" + std.prelude.to_string(issue.native_code) + " " + issue.message)
    println("elapsed_ns=" + std.prelude.to_string(end - start))
    failing := mode == "unavailable" || mode == "timeout" || mode == "auth" || mode == "malformed"
    if failing && issue.code == 0 { return 3 }
    if !failing && issue.code != 0 { return 4 }
    if end - start > 1000000000 { return 5 }
    if !c.closed || c.group_link.connection.state == 2 || c.fetch_link.connection.state == 2 || c.bootstrap_link.connection.state == 2 || c.heartbeat_link.connection.state == 2 { return 6 }
    if len(c.decoder.input.data) != 0 || len(c.decoder.output.records) != 0 || len(c.commit_snapshot) != 0 || len(c.queue) != 0 || len(c.assigned) != 0 || c.outstanding_delivery_id != 0 || c.outstanding_end_offset != 0 { println("retained transient state after close"); return 7 }
    if std.kafka.consumer_close(c*, 600).code != 0 { return 8 }
    if mode == "auth" && (issue.code != std.kafka.error_broker || issue.native_code != 30) { return 9 }
    if mode == "malformed" && issue.code != std.kafka.error_protocol { return 10 }
    println("Close recovery / bounded deadline / cleanup / repeated close: PASS")
    return 0
}
