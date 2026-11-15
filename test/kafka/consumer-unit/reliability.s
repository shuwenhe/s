package main
import ("std.kafka"; "std.time")
func reliability_checks() int {
    ends := std.kafka.endpoint[]()
    ends = append(ends, std.kafka.endpoint { host: "127.0.0.1", port: 19092 })
    c, problem := std.kafka.consumer_new(std.kafka.consumer_config { bootstrap: ends, group_id: "reliability" })
    if problem.code != 0 { return 110 }
    now, clock_error := std.time.monotonic_clock()
    c.state = 6
    c.member_id = "expired"
    c.generation_id = 1
    c.assignment_epoch = 1
    c.last_poll_ns = now
    c.last_heartbeat_ns = now - 11000000000
    c.assigned = append(c.assigned, std.kafka.topic_partition { topic: "t", partition_id: 0, processed_offset: 0 })
    c.outstanding_delivery_id = 1
    c.outstanding_epoch = 1
    c.outstanding_end_offset = 1
    c.decoder = std.kafka.consumer_decoder_new("decoder-bytes", 0, 0, false)
    c.commit_snapshot = c.assigned
    issue := std.kafka.consumer_ack(c*, 1)
    if issue.code != std.kafka.error_rebalance || c.outstanding_delivery_id != 0 || len(c.decoder.input.data) != 0 || len(c.commit_snapshot) != 0 { println("expired ACK or revoked decoder state retained"); return 111 }
    fresh, fresh_error := std.kafka.consumer_new(c.config)
    fresh.state = 6
    fresh.member_id = "maxpoll"
    fresh.generation_id = 1
    fresh.assignment_epoch = 1
    fresh.last_heartbeat_ns = now
    fresh.last_poll_ns = now - fresh.config.max_poll_interval_ms * 1000000 - 1
    fresh.outstanding_delivery_id = 2
    fresh.outstanding_epoch = 1
    fresh.decoder = std.kafka.consumer_decoder_new("pending", 0, 0, false)
    empty, poll_error := std.kafka.consumer_poll(fresh*, 1)
    if poll_error.code != std.kafka.error_poll_interval || fresh.outstanding_delivery_id != 0 || len(fresh.decoder.input.data) != 0 { return 112 }
    println("Expired ACK, outstanding poll liveness and revoke cleanup: PASS")
    return 0
}
