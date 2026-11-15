package main
import ("std.kafka"; "std.time")
func offset_checks() int {
    c := std.kafka.consumer { initialized: true, state: 6, generation_id: 7, assignment_epoch: 3 }
    endpoints := std.kafka.endpoint[]()
    endpoints = append(endpoints, std.kafka.endpoint { host: "127.0.0.1", port: 19092 })
    configured, config_error := std.kafka.consumer_new(std.kafka.consumer_config { bootstrap: endpoints, group_id: "offset-unit" })
    c.config = configured.config
    ack_now, ack_clock_error := std.time.monotonic_clock()
    c.last_poll_ns = ack_now
    c.last_heartbeat_ns = ack_now
    c.assigned = append(c.assigned, std.kafka.topic_partition { topic: "topic", partition_id: 0, offset: 100, processed_offset: 42, committed_offset: 42, processed_valid: true })
    c.outstanding_delivery_id = 9
    c.outstanding_epoch = 3
    c.outstanding_partition = 0
    c.outstanding_end_offset = 44
    before := std.kafka.consumer_commit_candidates(c*)
    if len(before) != 0 { return 80 }
    wrong := std.kafka.consumer_ack(c*, 8)
    if wrong.code == 0 || c.assigned[0].processed_offset != 42 { return 81 }
    good := std.kafka.consumer_ack(c*, 9)
    if good.code != 0 || c.assigned[0].processed_offset != 44 || c.outstanding_delivery_id != 0 { return 82 }
    duplicate := std.kafka.consumer_ack(c*, 9)
    if duplicate.code == 0 { return 83 }
    pending := std.kafka.consumer_commit_candidates(c*)
    if len(pending) != 1 || pending[0].offset != 44 { return 84 }
    c.outstanding_delivery_id = 10
    c.outstanding_end_offset = 99
    not_acked := std.kafka.consumer_commit_candidates(c*)
    if not_acked[0].offset != 44 { return 85 }
    c.commit_snapshot = pending
    c.commit_epoch = 3
    c.commit_generation = 7
    failed_body := commit_body(7)
    failed := std.kafka.consumer_apply_commit(c*, failed_body)
    if failed.code != std.kafka.error_broker || failed.native_code != 7 || c.assigned[0].committed_offset != 42 { return 86 }
    retry := std.kafka.consumer_commit_candidates(c*)
    if len(retry) != 1 || retry[0].offset != 44 { return 87 }
    confirmed_body := commit_body(0)
    confirmed := std.kafka.consumer_apply_commit(c*, confirmed_body)
    if confirmed.code != 0 || c.assigned[0].committed_offset != 44 || c.assigned[0].processed_offset != 44 { return 88 }
    request, problem := std.kafka.consumer_build_offset_commit("client", 1, "group", "member", 7, pending)
    if problem.code != 0 { return 89 }
    cursor := std.kafka.new_cursor(request, 1048576)
    if std.kafka.read_int(cursor*, 2) != 8 || std.kafka.read_int(cursor*, 2) != 2 { return 90 }
    c.assignment_epoch = 4
    stale := std.kafka.consumer_ack(c*, 10)
    if stale.code != std.kafka.error_rebalance { return 91 }
    c.assignment_epoch = 3
    c.outstanding_delivery_id = 0
    c.config.session_timeout_ms = 10000
    c.config.max_poll_interval_ms = 300000
    c.config.connect_timeout_ms = 1
    c.config.request_timeout_ms = 10
    p := c.assigned[0]
    p.processed_offset = 45
    c.assigned[0] = p
    now, clock_error := std.time.monotonic_clock()
    c.last_poll_ns = now
    c.last_heartbeat_ns = now
    c.next_heartbeat_ns = now + 3000000000
    lost := std.kafka.consumer_commit(c*, 10)
    if lost.code != std.kafka.error_transport || c.assigned[0].processed_offset != 45 || c.assigned[0].committed_offset != 44 { return 92 }
    expected := std.kafka.topic_partition[]()
    expected = append(expected, std.kafka.topic_partition { topic: "topic", partition_id: 0 })
    expected = append(expected, std.kafka.topic_partition { topic: "topic", partition_id: 1 })
    mixed_results, mixed_error := std.kafka.consumer_parse_offsets(mixed_commit_body(30), expected, 8)
    if mixed_error.native_code != 30 { return 93 }
    fenced_results, fenced_error := std.kafka.consumer_parse_offsets(mixed_commit_body(22), expected, 8)
    if fenced_error.native_code != 22 { return 94 }
    authorization := std.kafka.error { code: std.kafka.error_broker, native_code: 30 }
    terminal := std.kafka.consumer_handle_commit_error(c*, authorization)
    if terminal.native_code != 30 || c.state != 9 { return 95 }
    println("Consumer explicit ACK / contiguous commit gate / retry / confirmed offset / stale epoch: PASS")
    return 0
}
func commit_body(int status) string {
    w := std.kafka.new_writer(100)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_string(w*, "topic")
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, 0, 4)
    std.kafka.put_int(w*, status, 2)
    return w.data
}

func mixed_commit_body(int second_status) string {
    w := std.kafka.new_writer(100)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_string(w*, "topic")
    std.kafka.put_int(w*, 2, 4)
    std.kafka.put_int(w*, 0, 4)
    std.kafka.put_int(w*, 7, 2)
    std.kafka.put_int(w*, 1, 4)
    std.kafka.put_int(w*, second_status, 2)
    return w.data
}
