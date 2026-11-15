package main
import ("std.kafka"; "std.tcp")
func patch_payload(string batch, int position, int byte) string {
    head, e1 := std.tcp.slice(batch, 0, 17)
    prefix, e2 := std.tcp.slice(batch, 21, position)
    suffix, e3 := std.tcp.slice(batch, position + 1, len(batch))
    payload := prefix + std.kafka.byte_string(byte) + suffix
    w := std.kafka.new_writer(1048576)
    std.kafka.put_raw(w*, head)
    crc := std.kafka.crc32c(payload)
    std.kafka.put_int(w*, crc, 4)
    std.kafka.put_raw(w*, payload)
    return w.data
}
func decode_cases(string batch) int {
    compressed, compressed_error := std.kafka.decode_record_batches(patch_payload(batch, 22, 1), 3, 42)
    if compressed_error.code != std.kafka.error_unsupported || len(compressed.records) != 0 || compressed.next_offset != 42 { return 40 }
    controlled, control_error := std.kafka.decode_record_batches(patch_payload(batch, 22, 32), 3, 42)
    if control_error.code != std.kafka.error_protocol || len(controlled.records) != 0 { return 41 }
    appended, append_error := std.kafka.decode_record_batches(patch_payload(batch, 22, 8), 3, 42)
    if append_error.code != 0 || appended.records[1].timestamp_ms != 100 { return 42 }
    gaps := patch_payload(batch, 26, 4)
    c := std.kafka.new_cursor(gaps, 1048576)
    std.kafka.take(c*, 61)
    first_size := std.kafka.read_varint(c*, 32)
    first_start := c.position
    std.kafka.read_int(c*, 1)
    std.kafka.read_varint(c*, 64)
    first_offset_position := c.position
    gaps = patch_payload(gaps, first_offset_position, 2)
    remaining := first_start + first_size - c.position
    std.kafka.take(c*, remaining)
    second_size := std.kafka.read_varint(c*, 32)
    std.kafka.read_int(c*, 1)
    std.kafka.read_varint(c*, 64)
    second_offset_position := c.position
    gaps = patch_payload(gaps, second_offset_position, 6)
    compacted, compact_error := std.kafka.decode_record_batches(gaps, 3, 42)
    if compact_error.code != 0 || compacted.records[0].offset != 43 || compacted.records[1].offset != 45 || compacted.next_offset != 47 { return 43 }
    horizon, horizon_error := std.kafka.decode_record_batches(patch_payload(batch, 22, 64), 3, 42)
    if horizon_error.code != 0 || horizon.records[1].timestamp_ms != 99 { return 46 }
    future := std.kafka.new_writer(1048576)
    std.kafka.put_int(future*, 44, 8)
    future_tail, future_error := std.tcp.slice(batch, 8, len(batch))
    std.kafka.put_raw(future*, future_tail)
    partial, slice_error := std.tcp.slice(future.data, 0, 30)
    decoder := std.kafka.consumer_decoder_new(batch + partial, 3, 42, true)
    while decoder.stage != 4 && decoder.problem.code == 0 { std.kafka.consumer_decoder_step(decoder*) }
    if decoder.problem.code != 0 || !decoder.output.partial_tail || decoder.output.next_offset != 44 || len(decoder.output.records) != 2 { return 44 }
    overlapping, overlap_error := std.kafka.decode_record_batches(batch + batch, 3, 42)
    if overlap_error.code != std.kafka.error_protocol || len(overlapping.records) != 0 { return 45 }
    marker_key := std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(1)
    marker_value := marker_key + std.kafka.byte_string(0) + std.kafka.byte_string(0)
    markers := std.kafka.message[]()
    markers = append(markers, std.kafka.message { key: std.kafka.bytes(marker_key), value: std.kafka.bytes(marker_value), timestamp_ms: 100 })
    marker, marker_error := std.kafka.encode_record_batch(markers)
    marker = patch_payload(marker, 22, 32)
    k := 43
    while k < 53 { marker = patch_payload(marker, k, 0); k = k + 1 }
    marker = patch_payload(marker, 50, 7)
    suppressed, suppress_error := std.kafka.decode_record_batches(marker, 3, 0)
    if suppress_error.code != 0 || len(suppressed.records) != 0 || suppressed.next_offset != 1 { return 47 }
    invalid_headers := std.kafka.header[]()
    invalid_headers = append(invalid_headers, std.kafka.header { key: std.kafka.byte_string(255) })
    invalid_records := std.kafka.message[]()
    invalid_records = append(invalid_records, std.kafka.message { headers: invalid_headers })
    invalid_batch, invalid_encode_error := std.kafka.encode_record_batch(invalid_records)
    invalid_decoded, invalid_error := std.kafka.decode_record_batches(invalid_batch, 0, 0)
    if invalid_error.code != std.kafka.error_protocol || len(invalid_decoded.records) != 0 { return 48 }
    println("Consumer valid-CRC compression rejection/control/log-append/compaction/partial-tail: PASS")
    return 0
}
