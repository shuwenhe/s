package std.kafka
import "std.time"

func _kc_now() int {
    now, problem := std.time.monotonic_clock()
    if problem.code != 0 { return -1 }
    return now
}
func _kc_link_ready(consumer_link* link, endpoint target, string client, int deadline, int connect_timeout, int request_timeout) error {
    now := _kc_now()
    if now < 0 { return failure(error_transport, "consumer monotonic clock failed") }
    if now >= deadline { return error {} }
    if link.connection.state != 2 {
        budget := (deadline - now + 999999) / 1000000
        if budget > connect_timeout { budget = connect_timeout }
        b, problem := broker_connect(target.host, target.port, client, budget)
        if problem.code != 0 { return problem }
        link.connection = b
        link.peer_host = target.host
        link.peer_port = target.port
        link.state = 0
        link.versions = api_version[]()
        link.negotiating = false
    }
    if len(link.versions) > 0 { return error {} }
    if !link.negotiating {
        request := broker_build_api_versions_request(client, link.connection.correlation_id)
        problem := consumer_exchange_begin(link*, request, request_timeout)
        if problem.code != 0 { return problem }
        link.negotiating = true
    }
    problem := consumer_exchange_step(link*, 0)
    if problem.code != 0 { return problem }
    if link.state == 4 {
        versions, parse_error := broker_parse_api_versions_response(link.body)
        if parse_error.code != 0 { return parse_error }
        link.versions = versions
        link.negotiating = false
        link.state = 0
    }
    return error {}
}
func consumer_subscribe(consumer* c, string[] topics) error {
    if !c.initialized || c.closed { return failure(error_closed, "consumer closed") }
    payload, problem := consumer_subscription(topics)
    if problem.code != 0 { return problem }
    if c.state != 0 { return failure(error_invalid, "subscribe before polling; reopen to change subscription") }
    c.topics = topics
    c.metadata_topics = topics
    c.state = 1
    c.last_poll_ns = _kc_now()
    return error {}
}
func _kc_revoke(consumer* c, bool forget_member) {
    c.assigned = topic_partition[]()
    c.queue = message[]()
    c.queue_cursor = 0
    c.queue_partition = 0
    c.queue_end_offset = 0
    c.decoder = consumer_decoder {}
    c.commit_snapshot = topic_partition[]()
    c.commit_epoch = -1
    c.commit_generation = -1
    c.outstanding_epoch = 0
    c.outstanding_partition = 0
    c.outstanding_end_offset = 0
    c.joined = consumer_join_result {}
    c.outstanding_delivery_id = 0
    c.assignment_epoch = c.assignment_epoch + 1
    c.generation_id = -1
    c.offsets_loaded = false
    c.coordinator_retry = false
    if forget_member { c.member_id = "" }
    link := c.group_link
    consumer_link_close(link*)
    c.group_link = link
    heartbeat := c.heartbeat_link
    consumer_link_close(heartbeat*)
    c.heartbeat_link = heartbeat
    fetch := c.fetch_link
    consumer_link_close(fetch*)
    c.fetch_link = fetch
    c.group_operation = 0
    c.fetch_operation = 0
}
func _kc_recover(consumer* c, error problem) error {
    c.last_error = problem
    retry := problem.code == error_transport || problem.code == error_timeout
    if problem.code == error_broker {
        code := problem.native_code
        retry = code == 14 || code == 15 || code == 16 || code == 22 || code == 25 || code == 27 || code == 6 || code == 5 || code == 7
    }
    if !retry { c.state = 9; return problem }
    forget := problem.native_code == 25
    _kc_revoke(c*, forget)
    c.state = 1
    c.metadata_topics = c.topics
    c.bootstrap_operation = 0
    link := c.bootstrap_link
    consumer_link_close(link*)
    c.bootstrap_link = link
    c.bootstrap_index = c.bootstrap_index + 1
    c.retry_at_ns = _kc_now() + 100000000
    return problem
}
func _kc_metadata_step(consumer* c, int caller_deadline) error {
    deadline := consumer_connect_deadline(c*, caller_deadline, false)
    link := c.bootstrap_link
    index := c.bootstrap_index % len(c.config.bootstrap)
    target := c.config.bootstrap[index]
    problem := _kc_link_ready(link*, target, c.config.client_id, deadline, c.config.connect_timeout_ms, c.config.request_timeout_ms)
    c.bootstrap_link = link
    if problem.code != 0 { return problem }
    if len(link.versions) == 0 { return error {} }
    if c.bootstrap_operation == 0 {
        api := 3
        version := 4
        if c.state == 2 { api = 10; version = 1 }
        if !consumer_supports(link.versions, api, version) { return failure(error_unsupported, "consumer metadata/coordinator version unavailable") }
        request := ""
        issue := error {}
        if api == 3 {
            encoded, problem := consumer_build_metadata(c.config.client_id, link.connection.correlation_id, c.metadata_topics)
            request = encoded
            issue = problem
        } else {
            encoded, problem := consumer_build_find(c.config.client_id, link.connection.correlation_id, c.config.group_id)
            request = encoded
            issue = problem
        }
        if issue.code != 0 { return issue }
        issue = consumer_exchange_begin(link*, request, c.config.request_timeout_ms)
        if issue.code != 0 { return issue }
        c.bootstrap_operation = api
    }
    issue := consumer_exchange_step(link*, 0)
    c.bootstrap_link = link
    if issue.code != 0 { return issue }
    if link.state != 4 { return error {} }
    operation := c.bootstrap_operation
    c.bootstrap_operation = 0
    if operation == 3 {
        meta, parse_error := consumer_parse_metadata(link.body)
        if parse_error.code != 0 { return parse_error }
        i := 0
        while i < len(c.metadata_topics) { if !_kc_contains(meta.topics, c.metadata_topics[i]) { return failure(error_protocol, "Metadata omitted requested topic") } i = i + 1 }
        if c.state == 6 {
            changed := consumer_metadata_changed(c.metadata, meta, c.topics)
            c.metadata = meta
            c.next_metadata_ns = _kc_now() + 30000000000
            if changed {
                _kc_revoke(c*, false)
                c.state = 1
                c.metadata_topics = c.topics
                return failure(error_rebalance, "topic topology changed; assignment revoked")
            }
            return error {}
        }
        c.metadata = meta
        if c.state == 4 { c.state = 5 } else { c.state = 2 }
    } else {
        coordinator, parse_error := consumer_parse_find(link.body)
        if parse_error.code != 0 { return parse_error }
        c.coordinator = coordinator
        if c.coordinator_retry { c.state = 11 } else { c.state = 3 }
    }
    return error {}
}
func _kc_group_step(consumer* c, int caller_deadline) error {
    deadline := consumer_connect_deadline(c*, caller_deadline, false)
    link := c.group_link
    problem := _kc_link_ready(link*, c.coordinator, c.config.client_id, deadline, c.config.connect_timeout_ms, c.config.request_timeout_ms)
    c.group_link = link
    if problem.code != 0 { return problem }
    if len(link.versions) == 0 { return error {} }
    api := 11
    version := 2
    if c.state == 5 { api = 14; version = 1 }
    if !consumer_supports(link.versions, api, version) { return failure(error_unsupported, "consumer group API version unavailable") }
    if c.group_operation == 0 {
        request := ""
        issue := error {}
        if api == 11 {
            encoded, problem := consumer_build_join(c.config.client_id, link.connection.correlation_id, c.config.group_id, c.member_id, c.topics, c.config.session_timeout_ms, c.config.rebalance_timeout_ms)
            request = encoded
            issue = problem
        } else {
            assignments := member_assignment[]()
            if c.member_id == c.joined.leader_id {
                calculated, assignment_error := consumer_range_assign(c.joined.members, c.metadata)
                if assignment_error.code != 0 { return assignment_error }
                assignments = calculated
            }
            encoded, problem := consumer_build_sync(c.config.client_id, link.connection.correlation_id, c.config.group_id, c.member_id, c.generation_id, assignments)
            request = encoded
            issue = problem
        }
        if issue.code != 0 { return issue }
        budget := c.config.rebalance_timeout_ms + c.config.request_timeout_ms
        issue = consumer_exchange_begin(link*, request, budget)
        if issue.code != 0 { return issue }
        c.group_operation = api
    }
    issue := consumer_exchange_step(link*, 0)
    c.group_link = link
    if issue.code != 0 { return issue }
    if link.state != 4 { return error {} }
    operation := c.group_operation
    c.group_operation = 0
    if operation == 11 {
        joined, parse_error := consumer_parse_join(link.body)
        if parse_error.code != 0 { return parse_error }
        c.joined = joined
        c.member_id = joined.member_id
        c.generation_id = joined.generation_id
        c.next_heartbeat_ns = _kc_now()
        c.last_heartbeat_ns = c.next_heartbeat_ns
        if c.member_id == joined.leader_id {
            topics := string[]()
            i := 0
            while i < len(joined.members) {
                member := joined.members[i]
                j := 0
                while j < len(member.topics) { topic := member.topics[j]; if !_kc_contains(topics, topic) { topics = append(topics, topic) } j = j + 1 }
                i = i + 1
            }
            c.metadata_topics = topics
            c.state = 4
        } else { c.state = 5 }
    } else {
        assigned, parse_error := consumer_parse_sync(link.body)
        if parse_error.code != 0 { return parse_error }
        i := 0
        while i < len(assigned) {
            p := assigned[i]
            if !_kc_contains(c.topics, p.topic) { return failure(error_protocol, "SyncGroup assigned unsubscribed topic") }
            found := false
            j := 0
            while j < len(c.metadata.partitions) {
                known := c.metadata.partitions[j]
                if known.topic == p.topic && known.partition_id == p.partition_id { p.leader_id = known.leader_id; found = true }
                j = j + 1
            }
            if !found { return failure(error_protocol, "SyncGroup assigned unknown partition") }
            assigned[i] = p
            i = i + 1
        }
        c.assigned = assigned
        c.assignment_epoch = c.assignment_epoch + 1
        c.state = 7
        c.offsets_loaded = false
        c.last_error = error {}
        c.last_heartbeat_ns = _kc_now()
        c.last_poll_ns = c.last_heartbeat_ns
    }
    return error {}
}
func _kc_heartbeat_step(consumer* c, int caller_deadline) error {
    if c.generation_id < 0 || c.member_id == "" { return error {} }
    now := _kc_now()
    if now < c.next_heartbeat_ns && c.heartbeat_link.state == 0 { return error {} }
    link := c.heartbeat_link
    deadline := consumer_connect_deadline(c*, caller_deadline, true)
    problem := _kc_link_ready(link*, c.coordinator, c.config.client_id, deadline, c.config.connect_timeout_ms, c.config.request_timeout_ms)
    c.heartbeat_link = link
    if problem.code != 0 { return problem }
    if len(link.versions) == 0 { return error {} }
    if link.state == 0 {
        if !consumer_supports(link.versions, 12, 1) { return failure(error_unsupported, "Heartbeat v1 unavailable") }
        request, issue := consumer_build_membership(c.config.client_id, link.connection.correlation_id, c.config.group_id, c.member_id, c.generation_id, 12)
        if issue.code != 0 { return issue }
        issue = consumer_exchange_begin(link*, request, c.config.request_timeout_ms)
        if issue.code != 0 { return issue }
    }
    issue := consumer_exchange_step(link*, 0)
    c.heartbeat_link = link
    if issue.code != 0 { return issue }
    if link.state == 4 {
        parse_error := consumer_parse_membership(link.body)
        link.state = 0
        c.heartbeat_link = link
        if parse_error.code != 0 {
            if parse_error.native_code == 27 && (c.state == 4 || c.state == 5) {
                c.next_heartbeat_ns = _kc_now() + c.config.heartbeat_interval_ms * 1000000
                return error {}
            }
            return parse_error
        }
        c.last_heartbeat_ns = _kc_now()
        c.next_heartbeat_ns = c.last_heartbeat_ns + c.config.heartbeat_interval_ms * 1000000
        if c.state == 11 { c.state = 6; c.coordinator_retry = false }
    }
    return error {}
}
// Enforce local ownership deadlines before touching pending group/data state.
func consumer_check_liveness(consumer* c, int now) error {
    if c.state != 6 && c.state != 11 && !(c.state == 2 && c.coordinator_retry) { return error {} }
    if now < 0 { return failure(error_transport, "consumer monotonic clock failed") }
    if now - c.last_poll_ns >= c.config.max_poll_interval_ms * 1000000 {
        _kc_revoke(c*, true)
        bootstrap := c.bootstrap_link
        consumer_link_close(bootstrap*)
        c.bootstrap_link = bootstrap
        c.bootstrap_operation = 0
        c.state = 10
        c.last_error = failure(error_poll_interval, "maximum poll interval exceeded; call poll to rejoin")
        return c.last_error
    }
    if now - c.last_heartbeat_ns >= c.config.session_timeout_ms * 1000000 {
        _kc_revoke(c*, true)
        c.state = 1
        c.metadata_topics = c.topics
        c.bootstrap_operation = 0
        bootstrap := c.bootstrap_link
        consumer_link_close(bootstrap*)
        c.bootstrap_link = bootstrap
        c.coordinator_retry = false
        c.last_error = failure(error_rebalance, "consumer session expired; assignment revoked")
        return c.last_error
    }
    return error {}
}
func _kc_service_once(consumer* c, int deadline) error {
    if c.state == 9 || c.state == 10 { return c.last_error }
    now := _kc_now()
    if now >= deadline || now < c.retry_at_ns { return error {} }
    liveness := consumer_check_liveness(c*, now)
    if liveness.code != 0 { return liveness }
    issue := error {}
    if c.state == 4 || c.state == 5 || c.state == 6 || c.state == 7 || c.state == 11 { issue = _kc_heartbeat_step(c*, deadline) }
    if issue.code == 0 && _kc_now() < deadline {
        if c.state == 1 || c.state == 2 || c.state == 4 { issue = _kc_metadata_step(c*, deadline) }
        if c.state == 3 || c.state == 5 { issue = _kc_group_step(c*, deadline) }
        if c.state == 7 { issue = _kc_initial_offsets(c*, deadline) }
        if c.state == 6 && (_kc_now() >= c.next_metadata_ns || c.bootstrap_operation == 3) {
            c.metadata_topics = c.topics
            issue = _kc_metadata_step(c*, deadline)
            if issue.code == error_rebalance { return issue }
        }
        if issue.code == 0 && c.state == 6 {
            commit_issue := _kc_commit_step(c*, deadline)
            if commit_issue.code != 0 {
                return consumer_handle_commit_error(c*, commit_issue)
            }
        }
    }
    if issue.code != 0 { return _kc_recover(c*, issue) }
    return error {}
}
func consumer_service(consumer* c, int timeout_ms) error {
    if !c.initialized || c.closed { return failure(error_closed, "consumer closed") }
    if timeout_ms < 1 || timeout_ms > 2147483647 { return failure(error_invalid, "consumer service timeout") }
    deadline := _kc_now() + timeout_ms * 1000000
    while _kc_now() < deadline {
        issue := _kc_service_once(c*, deadline)
        if issue.code != 0 { return issue }
        std.time.sleep_ms(1)
    }
    return error {}
}
// Close never rejoins a group. Retry a stale transport within one caller budget;
// an already absent member is the desired postcondition after an ambiguous Leave.
func _kc_close_leave_once(consumer* c, consumer_link* leave, int deadline) error {
    problem := error {}
    while _kc_now() < deadline {
        problem = _kc_link_ready(leave*, c.coordinator, c.config.client_id, deadline, c.config.connect_timeout_ms, c.config.request_timeout_ms)
        if problem.code != 0 || len(leave.versions) > 0 { break }
        std.time.sleep_ms(1)
    }
    if problem.code != 0 { return problem }
    if len(leave.versions) == 0 { return failure(error_timeout, "close reconnect deadline") }
    if !consumer_supports(leave.versions, 13, 1) { return failure(error_unsupported, "LeaveGroup v1 unavailable") }
    remaining := (deadline - _kc_now() + 999999) / 1000000
    if remaining < 1 { return failure(error_timeout, "LeaveGroup close deadline") }
    request, build_error := consumer_build_membership(c.config.client_id, leave.connection.correlation_id, c.config.group_id, c.member_id, c.generation_id, 13)
    if build_error.code != 0 { return build_error }
    problem = consumer_exchange_begin(leave*, request, remaining)
    while problem.code == 0 && leave.state != 4 && _kc_now() < deadline { problem = consumer_exchange_step(leave*, 1) }
    if problem.code != 0 { return problem }
    if leave.state != 4 { return failure(error_timeout, "LeaveGroup close deadline") }
    problem = consumer_parse_membership(leave.body)
    if problem.code == error_broker && problem.native_code == 25 { return error {} }
    return problem
}
func _kc_close_coordinator(consumer* c, int deadline) error {
    issue := failure(error_timeout, "close coordinator discovery deadline")
    i := 0
    while i < len(c.config.bootstrap) && _kc_now() < deadline {
        link := consumer_link {}
        target := c.config.bootstrap[i]
        issue = error {}
        while issue.code == 0 && len(link.versions) == 0 && _kc_now() < deadline {
            issue = _kc_link_ready(link*, target, c.config.client_id, deadline, c.config.connect_timeout_ms, c.config.request_timeout_ms)
            if issue.code == 0 && len(link.versions) == 0 { std.time.sleep_ms(1) }
        }
        if issue.code == 0 && len(link.versions) > 0 {
            if !consumer_supports(link.versions, 10, 1) { issue = failure(error_unsupported, "FindCoordinator v1 unavailable during close") }
            if issue.code == 0 {
                request, build_error := consumer_build_find(c.config.client_id, link.connection.correlation_id, c.config.group_id)
                issue = build_error
                remaining := (deadline - _kc_now() + 999999) / 1000000
                if remaining < 1 { issue = failure(error_timeout, "close coordinator discovery deadline") }
                if issue.code == 0 { issue = consumer_exchange_begin(link*, request, remaining) }
                while issue.code == 0 && link.state != 4 && _kc_now() < deadline { issue = consumer_exchange_step(link*, 1) }
                if issue.code == 0 && link.state != 4 { issue = failure(error_timeout, "close coordinator discovery deadline") }
                if issue.code == 0 {
                    found, parse_error := consumer_parse_find(link.body)
                    issue = parse_error
                    if issue.code == 0 { c.coordinator = found }
                }
            }
        } else if issue.code == 0 { issue = failure(error_timeout, "close coordinator discovery deadline") }
        consumer_link_close(link*)
        if issue.code == 0 { return issue }
        if issue.code != error_transport && issue.code != error_timeout && issue.code != error_broker { return issue }
        if issue.code == error_broker && issue.native_code != 14 && issue.native_code != 15 && issue.native_code != 16 { return issue }
        i = i + 1
    }
    return issue
}
func consumer_close(consumer* c, int timeout_ms) error {
    if c.closed || !c.initialized { c.closed = true; return error {} }
    first := error {}
    if timeout_ms < 1 || timeout_ms > 2147483647 { first = failure(error_invalid, "consumer close timeout") }
    deadline := _kc_now() + timeout_ms * 1000000
    commit_failure := error {}
    if first.code == 0 && c.config.auto_commit && c.state == 6 { commit_failure = consumer_commit(c*, timeout_ms) }
    if first.code == 0 && c.member_id != "" {
        leave := c.group_link
        if leave.state > 0 && leave.state < 4 { consumer_link_close(leave*) }
        attempt := 0
        while attempt < 3 {
            first = _kc_close_leave_once(c*, leave*, deadline)
            if first.code == 0 { break }
            retry := first.code == error_transport || first.code == error_timeout
            if first.code == error_broker { retry = first.native_code == 14 || first.native_code == 15 || first.native_code == 16 }
            if !retry || _kc_now() >= deadline || attempt == 2 { break }
            consumer_link_close(leave*)
            // First retry the known coordinator for a remotely idled socket.
            // On a second failure, resolve migration without JoinGroup/SyncGroup.
            if attempt == 1 || first.code == error_broker {
                first = _kc_close_coordinator(c*, deadline)
                if first.code != 0 { break }
            }
            attempt = attempt + 1
        }
        c.group_link = leave
    }
    leave_failure := first
    if commit_failure.code != 0 { first = commit_failure }
    bootstrap := c.bootstrap_link
    cleanup_error := consumer_link_close(bootstrap*)
    if first.code == 0 { first = cleanup_error }
    group := c.group_link
    problem := consumer_link_close(group*)
    if first.code == 0 { first = problem }
    heartbeat := c.heartbeat_link
    problem = consumer_link_close(heartbeat*)
    if first.code == 0 { first = problem }
    fetch := c.fetch_link
    problem = consumer_link_close(fetch*)
    if first.code == 0 { first = problem }
    // Preserve caller configuration and diagnostics, not decoder/queue/snapshot
    // ownership. This runs even after invalid input or a failed LeaveGroup.
    c.assigned = topic_partition[]()
    c.queue = message[]()
    c.decoder = consumer_decoder {}
    c.commit_snapshot = topic_partition[]()
    c.joined = consumer_join_result {}
    c.metadata = consumer_metadata {}
    c.topics = string[]()
    c.metadata_topics = string[]()
    c.coordinator = endpoint {}
    c.member_id = ""
    c.bootstrap_link = bootstrap
    c.group_link = group
    c.heartbeat_link = heartbeat
    c.fetch_link = fetch
    c.generation_id = -1
    c.assignment_epoch = c.assignment_epoch + 1
    c.closed = true
    c.state = 0
    c.bootstrap_operation = 0
    c.group_operation = 0
    c.fetch_operation = 0
    c.queue_cursor = 0
    c.queue_partition = 0
    c.queue_end_offset = 0
    c.outstanding_delivery_id = 0
    c.outstanding_epoch = 0
    c.outstanding_partition = 0
    c.outstanding_end_offset = 0
    c.commit_epoch = 0
    c.commit_generation = -1
    c.commit_sequence = 0
    c.commit_completed = 0
    c.commit_error = error {}
    c.offsets_loaded = false
    c.coordinator_retry = false
    c.leave_error = leave_failure
    c.last_error = first
    return first
}

// Bound synchronous connects by scheduling/ownership deadlines. Pending socket
// exchanges still retain their own total request deadline across service calls.
func consumer_connect_deadline(consumer* c, int caller_deadline, bool heartbeat_role) int {
    deadline := caller_deadline
    if c.generation_id < 0 || c.member_id == "" { return deadline }
    session := c.last_heartbeat_ns + c.config.session_timeout_ms * 1000000
    poll := c.last_poll_ns + c.config.max_poll_interval_ms * 1000000
    if session < deadline { deadline = session }
    if poll < deadline { deadline = poll }
    if !heartbeat_role && c.next_heartbeat_ns < deadline { deadline = c.next_heartbeat_ns }
    return deadline
}
