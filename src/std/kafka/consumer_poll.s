package std.kafka
import "std.time"
func _kc_fetch_step(consumer* c, int caller_deadline) error {
    deadline := consumer_connect_deadline(c*, caller_deadline, false)
    if c.state != 6 || len(c.assigned) == 0 || c.outstanding_delivery_id != 0 || c.queue_cursor < len(c.queue) { return error {} }
    if c.fetch_operation == 3 {
        decoder := c.decoder
        consumer_decoder_step(decoder*)
        c.decoder = decoder
        if decoder.problem.code != 0 { return decoder.problem }
        if decoder.stage != 4 { return error {} }
        index := c.fetch_partition
        p := c.assigned[index]
        p.offset = decoder.output.next_offset
        c.assigned[index] = p
        c.queue = decoder.output.records
        c.queue_cursor = 0
        c.queue_partition = index
        c.queue_end_offset = p.offset
        if len(c.queue) == 0 {
            p.processed_offset = p.offset
            p.processed_valid = true
            c.assigned[index] = p
        }
        c.decoder = consumer_decoder {}
        c.fetch_operation = 0
        c.next_partition = (index + 1) % len(c.assigned)
        return error {}
    }
    index := c.next_partition % len(c.assigned)
    if c.fetch_operation == 1 { index = c.fetch_partition }
    p := c.assigned[index]
    target, endpoint_error := consumer_metadata_endpoint(c.metadata, p.leader_id)
    if endpoint_error.code != 0 { return endpoint_error }
    link := c.fetch_link
    if link.connection.state == 2 && (link.peer_host != target.host || link.peer_port != target.port) { consumer_link_close(link*) }
    issue := _kc_link_ready(link*, target, c.config.client_id, deadline, c.config.connect_timeout_ms, c.config.request_timeout_ms)
    c.fetch_link = link
    if issue.code != 0 || len(link.versions) == 0 { return issue }
    if !consumer_supports(link.versions, 1, 4) { return failure(error_unsupported, "Fetch v4 unavailable") }
    if c.fetch_operation == 0 {
        request, problem := consumer_build_fetch(c.config.client_id, link.connection.correlation_id, p.topic, p.partition_id, p.offset, 100, c.config.fetch_max_bytes)
        if problem.code != 0 { return problem }
        issue = consumer_exchange_begin(link*, request, c.config.request_timeout_ms)
        if issue.code != 0 { return issue }
        c.fetch_operation = 1
        c.fetch_partition = index
    }
    issue = consumer_exchange_step(link*, 0)
    c.fetch_link = link
    if issue.code != 0 { return issue }
    if link.state != 4 { return error {} }
    records, parse_error := consumer_parse_fetch(link.body, p.topic, p.partition_id)
    if parse_error.code != 0 { return parse_error }
    c.decoder = consumer_decoder_new(records.data, p.partition_id, p.offset, true)
    c.fetch_operation = 3
    return error {}
}
func consumer_poll(consumer* c, int timeout_ms) (consumer_batch,error) {
    empty := consumer_batch { timed_out: true }
    if !c.initialized || c.closed { return empty, failure(error_closed, "consumer closed") }
    if timeout_ms < 1 || timeout_ms > 2147483647 { return empty, failure(error_invalid, "consumer poll timeout") }
    now := _kc_now()
    liveness := consumer_check_liveness(c*, now)
    if liveness.code != 0 { return empty, liveness }
    if c.outstanding_delivery_id != 0 { return empty, failure(error_unacknowledged, "acknowledge prior delivery or service while processing") }
    c.last_poll_ns = now
    if c.state == 10 { c.state = 1; c.metadata_topics = c.topics; c.last_error = error {} }
    deadline := now + timeout_ms * 1000000
    while _kc_now() < deadline {
        issue := _kc_service_once(c*, deadline)
        if issue.code != 0 { return empty, issue }
        if c.state == 6 && c.queue_cursor < len(c.queue) {
            if c.next_delivery_id >= 9223372036854775807 { return empty, failure(error_bounds, "consumer delivery token exhausted") }
            out := consumer_batch { delivery_id: c.next_delivery_id, assignment_epoch: c.assignment_epoch }
            count := 0
            index := c.queue_partition
            topic := c.assigned[index].topic
            end_offset := c.assigned[index].processed_offset
            while c.queue_cursor < len(c.queue) && count < c.config.max_poll_records {
                record := c.queue[c.queue_cursor]
                out.records = append(out.records, consumed_record { topic: topic, data: record })
                end_offset = record.offset + 1
                c.queue_cursor = c.queue_cursor + 1
                count = count + 1
            }
            if c.queue_cursor == len(c.queue) {
                end_offset = c.queue_end_offset
                c.queue = message[]()
                c.queue_cursor = 0
            }
            c.outstanding_delivery_id = c.next_delivery_id
            c.outstanding_epoch = c.assignment_epoch
            c.outstanding_partition = index
            c.outstanding_end_offset = end_offset
            c.next_delivery_id = c.next_delivery_id + 1
            return out, error {}
        }
        if _kc_now() < deadline {
            issue = _kc_fetch_step(c*, deadline)
            if issue.code != 0 { problem := _kc_recover(c*, issue); return empty, problem }
        }
        std.time.sleep_ms(1)
    }
    return empty, error {}
}
func consumer_seek(consumer* c, string topic, int partition_id, int offset) error {
    if !c.initialized || c.closed { return failure(error_closed, "consumer closed") }
    if offset < 0 { return failure(error_invalid, "negative consumer seek") }
    if c.state != 6 && !(c.state == 9 && c.last_error.code == error_broker && c.last_error.native_code == 1) { return failure(error_rebalance, "seek requires current ownership") }
    if c.group_operation != 0 { return failure(error_invalid, "seek while group request pending") }
    index := consumer_partition_index(c.assigned, topic, partition_id)
    if index < 0 { return failure(error_invalid, "seek partition is not assigned") }
    i := 0
    while i < len(c.assigned) {
        p := c.assigned[i]
        // Discarding a queue must replay all unacknowledged records, even if the
        // seek targeted another partition. Processed progress is the safe floor.
        p.offset = p.processed_offset
        if i == index { p.offset = offset; p.processed_offset = offset; p.processed_valid = false }
        c.assigned[i] = p
        i = i + 1
    }
    c.assignment_epoch = c.assignment_epoch + 1
    c.outstanding_delivery_id = 0
    c.queue = message[]()
    c.queue_cursor = 0
    c.decoder = consumer_decoder {}
    c.fetch_operation = 0
    fetch := c.fetch_link
    consumer_link_close(fetch*)
    c.fetch_link = fetch
    c.state = 6
    c.last_error = error {}
    return error {}
}
