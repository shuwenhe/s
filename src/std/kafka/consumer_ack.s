package std.kafka
func consumer_ack(consumer* c, int delivery_id) error {
    if c.closed || !c.initialized { return failure(error_closed, "consumer closed") }
    now := _kc_now()
    liveness := consumer_check_liveness(c*, now)
    if liveness.code != 0 { return liveness }
    if c.state != 6 || c.outstanding_epoch != c.assignment_epoch { return failure(error_rebalance, "delivery assignment revoked") }
    if delivery_id < 1 || delivery_id != c.outstanding_delivery_id { return failure(error_invalid, "unknown or already acknowledged delivery") }
    index := c.outstanding_partition
    if index < 0 || index >= len(c.assigned) { return failure(error_rebalance, "delivery partition revoked") }
    p := c.assigned[index]
    if c.outstanding_end_offset < p.processed_offset && p.processed_valid { return failure(error_protocol, "noncontiguous consumer acknowledgment") }
    p.processed_offset = c.outstanding_end_offset
    p.processed_valid = true
    c.assigned[index] = p
    c.outstanding_delivery_id = 0
    return error {}
}
func consumer_commit_candidates(consumer* c) topic_partition[] {
    parts := topic_partition[]()
    i := 0
    while i < len(c.assigned) {
        p := c.assigned[i]
        if p.processed_valid && p.processed_offset != p.committed_offset {
            p.offset = p.processed_offset
            parts = append(parts, p)
        }
        i = i + 1
    }
    return parts
}
func consumer_apply_commit(consumer* c, string data) error {
    if c.commit_epoch != c.assignment_epoch || c.commit_generation != c.generation_id || c.state != 6 { return failure(error_rebalance, "commit generation revoked") }
    results, problem := consumer_parse_offsets(data, c.commit_snapshot, 8)
    if problem.code != 0 && problem.code != error_broker { return problem }
    i := 0
    while i < len(results) {
        r := results[i]
        if r.status == 0 {
            current := consumer_partition_index(c.assigned, r.topic, r.partition_id)
            snapshot := consumer_partition_index(c.commit_snapshot, r.topic, r.partition_id)
            if current < 0 || snapshot < 0 { return failure(error_rebalance, "commit partition revoked") }
            p := c.assigned[current]
            p.committed_offset = c.commit_snapshot[snapshot].offset
            c.assigned[current] = p
        }
        i = i + 1
    }
    return problem
}

func _kc_offset_error_rank(int status) int {
    if status == 0 { return 0 }
    if status == -1 || status == 7 || status == 13 || status == 14 || status == 15 || status == 16 || status == 19 || status == 20 { return 1 }
    if status == 22 || status == 25 || status == 27 { return 2 }
    return 3
}
func consumer_handle_commit_error(consumer* c, error issue) error {
    c.last_error = issue
    if issue.code == error_broker {
        rank := _kc_offset_error_rank(issue.native_code)
        if rank == 3 { c.state = 9; return issue }
        if rank == 2 { return _kc_recover(c*, issue) }
    }
    if issue.code == error_protocol || issue.code == error_bounds || issue.code == error_unsupported { return _kc_recover(c*, issue) }
    // Retriable persistence errors are visible without discarding ACKed progress.
    return issue
}
