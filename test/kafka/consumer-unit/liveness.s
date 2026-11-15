package main
import ("std.kafka"; "std.time")
func liveness_checks() int {
    bootstrap := std.kafka.endpoint[]()
    bootstrap = append(bootstrap, std.kafka.endpoint { host: "127.0.0.1", port: 9092 })
    c, problem := std.kafka.consumer_new(std.kafka.consumer_config { bootstrap: bootstrap, group_id: "group" })
    if problem.code != 0 { return 70 }
    c.state = 6
    c.generation_id = 1
    c.member_id = "m"
    c.last_poll_ns = 1
    c.last_heartbeat_ns = 1
    c.outstanding_delivery_id = 4
    issue := std.kafka.consumer_check_liveness(c*, 10000000001)
    if issue.code != std.kafka.error_rebalance || c.state != 1 || c.outstanding_delivery_id != 0 || c.member_id != "" { return 71 }
    c.state = 6
    c.member_id = "m"
    c.generation_id = 2
    c.last_poll_ns = 1
    c.last_heartbeat_ns = 300000000001
    issue2 := std.kafka.consumer_check_liveness(c*, 300000000002)
    if issue2.code != std.kafka.error_poll_interval || c.state != 10 || c.generation_id != -1 { return 72 }
    if std.kafka.consumer_close(c*, 100).code != 0 || std.kafka.consumer_close(c*, 100).code != 0 { return 73 }
    orphan := std.kafka.consumer { initialized: true, member_id: "orphan", config: c.config }
    close_error := std.kafka.consumer_close(orphan*, 10)
    if close_error.code == 0 || !orphan.closed { return 74 }
    delayed, delayed_error := std.kafka.consumer_new(c.config)
    delayed.state = 6
    delayed.member_id = "delayed"
    delayed.generation_id = 4
    now, clock_error := std.time.monotonic_clock()
    delayed.last_poll_ns = now - delayed.config.max_poll_interval_ms * 1000000 - 1
    delayed.last_heartbeat_ns = now
    ignored, poll_error := std.kafka.consumer_poll(delayed*, 1)
    if poll_error.code != std.kafka.error_poll_interval || delayed.state != 10 || delayed.generation_id != -1 { return 75 }
    before := std.kafka.consumer_metadata {}
    before.partitions = append(before.partitions, std.kafka.topic_partition { topic: "topic", partition_id: 0, leader_id: 1 })
    after := before
    after.partitions = append(after.partitions, std.kafka.topic_partition { topic: "topic", partition_id: 1, leader_id: 2 })
    topics := string[] { "topic" }
    same := std.kafka.consumer_metadata_changed(before, before, topics)
    changed := std.kafka.consumer_metadata_changed(before, after, topics)
    if same || !changed { return 76 }
    rediscovery, rediscovery_error := std.kafka.consumer_new(c.config)
    rediscovery.state = 2
    rediscovery.coordinator_retry = true
    rediscovery.generation_id = 7
    transport_error := std.kafka.error { code: std.kafka.error_transport }
    recovered := std.kafka._kc_recover(rediscovery*, transport_error)
    if rediscovery.coordinator_retry || rediscovery.state != 1 || rediscovery.generation_id != -1 { return 77 }
    bounded, bounded_error := std.kafka.consumer_new(c.config)
    bounded.state = 6
    bounded.generation_id = 3
    bounded.member_id = "bounded"
    bounded.last_poll_ns = 1000000000
    bounded.last_heartbeat_ns = 1000000000
    bounded.next_heartbeat_ns = 4000000000
    normal_deadline := std.kafka.consumer_connect_deadline(bounded*, 30000000000, false)
    heartbeat_deadline := std.kafka.consumer_connect_deadline(bounded*, 30000000000, true)
    if normal_deadline != 4000000000 || heartbeat_deadline != 11000000000 { return 78 }
    println("Consumer session/max-poll revocation and idempotent close: PASS")
    return 0
}
