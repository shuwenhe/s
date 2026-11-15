package main
import ("std.kafka"; "std.time"; "std.prelude")
func main() int {
    ends := std.kafka.endpoint[]()
    ends = append(ends, std.kafka.endpoint { host: "127.0.0.1", port: 39092 })
    cfg := std.kafka.consumer_config { bootstrap: ends, group_id: "audit-probe" }
    c, problem := std.kafka.consumer_new(cfg)
    if problem.code != 0 { return 1 }
    now, clock_error := std.time.monotonic_clock()
    c.state = 6
    c.generation_id = 1
    c.assignment_epoch = 1
    c.member_id = "expired-member"
    c.last_heartbeat_ns = now - 11000000000
    c.last_poll_ns = now
    c.assigned = append(c.assigned, std.kafka.topic_partition { topic: "topic", partition_id: 0, processed_offset: 0, committed_offset: -1 })
    c.outstanding_delivery_id = 1
    c.outstanding_epoch = 1
    c.outstanding_partition = 0
    c.outstanding_end_offset = 1
    issue := std.kafka.consumer_ack(c*, 1)
    println("expired_ack_code=" + std.prelude.to_string(issue.code))
    println("processed_after_ack=" + std.prelude.to_string(c.assigned[0].processed_offset))
    check := std.kafka.consumer_check_liveness(c*, now)
    println("subsequent_liveness_code=" + std.prelude.to_string(check.code))
    if issue.code != 0 || check.code != std.kafka.error_rebalance { return 2 }
    // Cleanup references: construct a consumer with pending decode state and no socket ownership.
    other, other_error := std.kafka.consumer_new(cfg)
    payload := "x"
    i := 0
    while i < 16 { payload = payload + payload; i = i + 1 }
    other.decoder = std.kafka.consumer_decoder_new(payload, 0, 0, false)
    other.commit_snapshot = append(other.commit_snapshot, std.kafka.topic_partition { topic: "retained", partition_id: 0 })
    close_error := std.kafka.consumer_close(other*, 10)
    println("close_code=" + std.prelude.to_string(close_error.code))
    println("closed_decoder_bytes=" + std.prelude.to_string(len(other.decoder.input.data)))
    println("closed_commit_snapshot=" + std.prelude.to_string(len(other.commit_snapshot)))
    if close_error.code != 0 || len(other.decoder.input.data) != 65536 || len(other.commit_snapshot) != 1 { return 3 }
    // Protocol bounds: multiple individually valid batches can exceed total record count.
    records := std.kafka.message[]()
    i = 0
    while i < 65 { records = append(records, std.kafka.message { value: std.kafka.bytes("x"), timestamp_ms: 0 }); i = i + 1 }
    encoded, encoded_error := std.kafka.encode_record_batch(records)
    if encoded_error.code != 0 { return 4 }
    combined := ""
    i = 0
    while i < 64 {
        // Rewrite base offset using bounded writer; CRC excludes base offset.
        w := std.kafka.new_writer(1048576)
        std.kafka.put_int(w*, i * 65, 8)
        cursor := std.kafka.new_cursor(encoded, 1048576)
        std.kafka.take(cursor*, 8)
        tail_size := len(encoded) - 8
        tail := std.kafka.take(cursor*, tail_size)
        std.kafka.put_raw(w*, tail)
        combined = combined + w.data
        i = i + 1
    }
    decoded, decode_error := std.kafka.decode_record_batches(combined, 0, 0)
    println("valid_record_count=4160 frame_bytes=" + std.prelude.to_string(len(combined)))
    println("multi_batch_decode_code=" + std.prelude.to_string(decode_error.code))
    if decode_error.code != std.kafka.error_bounds { return 5 }
    return 0
}
