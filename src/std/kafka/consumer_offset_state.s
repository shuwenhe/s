package std.kafka
import "std.time"

func _kc_initial_offsets(consumer* c, int caller_deadline) error {
    deadline := consumer_connect_deadline(c*, caller_deadline, false)
    if len(c.assigned) == 0 { c.offsets_loaded = true; c.state = 6; c.next_metadata_ns = _kc_now() + 30000000000; c.last_poll_ns = _kc_now(); return error {} }
    if !c.offsets_loaded {
        link := c.group_link
        if !consumer_supports(link.versions, 9, 2) { return failure(error_unsupported, "OffsetFetch v2 unavailable") }
        if c.group_operation == 0 {
            request, problem := consumer_build_offset_fetch(c.config.client_id, link.connection.correlation_id, c.config.group_id, c.assigned)
            if problem.code != 0 { return problem }
            issue := consumer_exchange_begin(link*, request, c.config.request_timeout_ms)
            if issue.code != 0 { return issue }
            c.group_operation = 9
        }
        issue := consumer_exchange_step(link*, 0)
        c.group_link = link
        if issue.code != 0 { return issue }
        if link.state != 4 { return error {} }
        results, problem := consumer_parse_offsets(link.body, c.assigned, 9)
        c.group_operation = 0
        if problem.code != 0 { return problem }
        i := 0
        while i < len(results) {
            r := results[i]
            index := consumer_partition_index(c.assigned, r.topic, r.partition_id)
            p := c.assigned[index]
            p.offset = r.offset
            p.processed_offset = r.offset
            p.committed_offset = r.offset
            p.processed_valid = false
            c.assigned[index] = p
            i = i + 1
        }
        c.offsets_loaded = true
        return error {}
    }
    index := -1
    if c.fetch_operation == 2 { index = c.fetch_partition } else {
        i := 0
        while i < len(c.assigned) { if c.assigned[i].offset < 0 { index = i; break } i = i + 1 }
    }
    if index < 0 {
        c.state = 6
        c.next_metadata_ns = _kc_now() + 30000000000
        c.last_poll_ns = _kc_now()
        c.next_commit_ns = c.last_poll_ns + c.config.auto_commit_interval_ms * 1000000
        return error {}
    }
    p := c.assigned[index]
    target, endpoint_error := consumer_metadata_endpoint(c.metadata, p.leader_id)
    if endpoint_error.code != 0 { return endpoint_error }
    link := c.fetch_link
    if link.connection.state == 2 && (link.peer_host != target.host || link.peer_port != target.port) { consumer_link_close(link*) }
    issue := _kc_link_ready(link*, target, c.config.client_id, deadline, c.config.connect_timeout_ms, c.config.request_timeout_ms)
    c.fetch_link = link
    if issue.code != 0 || len(link.versions) == 0 { return issue }
    if !consumer_supports(link.versions, 2, 1) { return failure(error_unsupported, "ListOffsets v1 unavailable") }
    expected := topic_partition[]()
    expected = append(expected, p)
    if c.fetch_operation == 0 {
        timestamp := -2
        if c.config.initial_offset == 1 { timestamp = -1 }
        request, problem := consumer_build_list_offsets(c.config.client_id, link.connection.correlation_id, expected, timestamp)
        if problem.code != 0 { return problem }
        issue = consumer_exchange_begin(link*, request, c.config.request_timeout_ms)
        if issue.code != 0 { return issue }
        c.fetch_operation = 2
        c.fetch_partition = index
    }
    issue = consumer_exchange_step(link*, 0)
    c.fetch_link = link
    if issue.code != 0 { return issue }
    if link.state != 4 { return error {} }
    results, problem := consumer_parse_offsets(link.body, expected, 2)
    if problem.code != 0 { return problem }
    if results[0].offset < 0 { return failure(error_protocol, "ListOffsets missing initial position") }
    p.offset = results[0].offset
    p.processed_offset = p.offset
    p.processed_valid = false
    c.assigned[index] = p
    c.fetch_operation = 0
    return error {}
}
func _kc_begin_commit(consumer* c) error {
    if c.state != 6 || c.generation_id < 0 { return failure(error_rebalance, "consumer commit requires stable membership") }
    if c.group_operation != 0 { return failure(error_invalid, "group operation pending") }
    snapshot := consumer_commit_candidates(c*)
    if len(snapshot) == 0 { return error {} }
    link := c.group_link
    if !consumer_supports(link.versions, 8, 2) { return failure(error_unsupported, "OffsetCommit v2 unavailable") }
    request, problem := consumer_build_offset_commit(c.config.client_id, link.connection.correlation_id, c.config.group_id, c.member_id, c.generation_id, snapshot)
    if problem.code != 0 { return problem }
    problem = consumer_exchange_begin(link*, request, c.config.request_timeout_ms)
    if problem.code != 0 { return problem }
    c.commit_snapshot = snapshot
    c.commit_epoch = c.assignment_epoch
    c.commit_generation = c.generation_id
    c.commit_sequence = c.commit_sequence + 1
    c.commit_error = error {}
    c.group_link = link
    c.group_operation = 8
    return error {}
}
func _kc_commit_step(consumer* c, int caller_deadline) error {
    deadline := consumer_connect_deadline(c*, caller_deadline, false)
    if c.group_operation != 8 {
        if !c.config.auto_commit || _kc_now() < c.next_commit_ns { return error {} }
        link := c.group_link
        ready := _kc_link_ready(link*, c.coordinator, c.config.client_id, deadline, c.config.connect_timeout_ms, c.config.request_timeout_ms)
        c.group_link = link
        if ready.code != 0 { return ready }
        if len(link.versions) == 0 { return error {} }
        c.next_commit_ns = _kc_now() + c.config.auto_commit_interval_ms * 1000000
        issue := _kc_begin_commit(c*)
        if issue.code != 0 || c.group_operation != 8 { return issue }
    }
    link := c.group_link
    issue := consumer_exchange_step(link*, 0)
    c.group_link = link
    if issue.code != 0 || link.state == 4 {
        if issue.code == 0 { issue = consumer_apply_commit(c*, link.body) }
        c.commit_error = issue
        c.commit_completed = c.commit_sequence
        c.group_operation = 0
        c.next_commit_ns = _kc_now() + c.config.auto_commit_interval_ms * 1000000
        if issue.code != 0 {
            c.last_error = issue
            if issue.code == error_broker && (issue.native_code == 22 || issue.native_code == 25 || issue.native_code == 27) { return issue }
            if issue.code == error_broker && (issue.native_code == 14 || issue.native_code == 15 || issue.native_code == 16) {
                group := c.group_link
                consumer_link_close(group*)
                c.group_link = group
                heartbeat := c.heartbeat_link
                consumer_link_close(heartbeat*)
                c.heartbeat_link = heartbeat
                c.state = 2
                c.coordinator_retry = true
                c.next_heartbeat_ns = _kc_now()
            }
            // Retryable commit failures keep ACKed progress and the failed snapshot.
            return issue
        }
    }
    return error {}
}
func consumer_commit(consumer* c, int timeout_ms) error {
    if !c.initialized || c.closed { return failure(error_closed, "consumer closed") }
    if timeout_ms < 1 || timeout_ms > 2147483647 { return failure(error_invalid, "consumer commit timeout") }
    if c.state != 6 { return failure(error_rebalance, "consumer commit membership not stable") }
    if c.group_operation != 8 {
        candidates := consumer_commit_candidates(c*)
        if len(candidates) == 0 { return error {} }
    }
    epoch := c.assignment_epoch
    deadline := _kc_now() + timeout_ms * 1000000
    while c.group_link.connection.state != 2 || len(c.group_link.versions) == 0 {
        check_now := _kc_now()
        liveness := consumer_check_liveness(c*, check_now)
        if liveness.code != 0 { return liveness }
        if _kc_now() >= deadline { return _k_network_error(110, "commit reconnect caller deadline") }
        link := c.group_link
        connect_deadline := consumer_connect_deadline(c*, deadline, false)
        ready := _kc_link_ready(link*, c.coordinator, c.config.client_id, connect_deadline, c.config.connect_timeout_ms, c.config.request_timeout_ms)
        c.group_link = link
        if ready.code != 0 { return ready }
        heartbeat := _kc_heartbeat_step(c*, deadline)
        if heartbeat.code != 0 { return _kc_recover(c*, heartbeat) }
        if c.assignment_epoch != epoch { return failure(error_rebalance, "commit assignment revoked") }
        std.time.sleep_ms(1)
    }
    if c.group_operation != 8 {
        problem := _kc_begin_commit(c*)
        if problem.code != 0 { return problem }
        if c.group_operation != 8 { return error {} }
    }
    sequence := c.commit_sequence
    while _kc_now() < deadline {
        problem := _kc_service_once(c*, deadline)
        if c.assignment_epoch != epoch { return failure(error_rebalance, "commit assignment revoked") }
        if c.commit_completed >= sequence { return c.commit_error }
        if problem.code != 0 { return problem }
        std.time.sleep_ms(1)
    }
    return _k_network_error(110, "consumer commit caller deadline; request may still be pending")
}
