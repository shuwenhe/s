package main
import ("std.kafka"; "std.tcp")
// Change a payload byte and recompute checksum, so structural failures cannot
// pass merely because the CRC check runs first.
func patch_batch(string batch, int index, int value) string {
    prefix, e1 := std.tcp.slice(batch, 21, index)
    suffix, e2 := std.tcp.slice(batch, index + 1, len(batch))
    payload := prefix + std.kafka.byte_string(value) + suffix
    header, e3 := std.tcp.slice(batch, 0, 17)
    w := std.kafka.new_writer(1048576)
    std.kafka.put_raw(w*, header)
    checksum := std.kafka.crc32c(payload)
    std.kafka.put_int(w*, checksum, 4)
    std.kafka.put_raw(w*, payload)
    return w.data
}
func malformed_checks() int {
    batch := golden_batch()
    if std.kafka.validate_record_batch(patch_batch(batch, 62, 1)).code != std.kafka.error_protocol { return 40 }
    if std.kafka.validate_record_batch(patch_batch(batch, 64, 2)).code != std.kafka.error_protocol { return 41 }
    if std.kafka.validate_record_batch(patch_batch(batch, 65, 3)).code != std.kafka.error_protocol { return 42 }
    if std.kafka.validate_record_batch(patch_batch(batch, 72, 1)).code != std.kafka.error_protocol { return 43 }
    if std.kafka.validate_record_batch(patch_batch(batch, 60, 2)).code != std.kafka.error_protocol { return 44 }
    if std.kafka.validate_record_batch(patch_batch(batch, 22, 1)).code != std.kafka.error_unsupported { return 45 }
    // BaseTimestamp=firstTimestamp is required even if maximumTimestamp agrees.
    changed := patch_batch(batch, 42, 1)
    changed = patch_batch(changed, 63, 2)
    if std.kafka.validate_record_batch(changed).code != std.kafka.error_protocol { return 46 }
    // Every prefix must fail; a complete valid batch is required.
    cut := 0
    while cut < len(batch) {
        prefix, slice_error := std.tcp.slice(batch, 0, cut)
        if std.kafka.validate_record_batch(prefix).code == 0 { return 47 }
        cut = cut + 1
    }
    // Timestamp difference across the full nonnegative int64 range must not wrap.
    records := std.kafka.message[]()
    records = append(records, std.kafka.message { timestamp_ms: 9223372036854775807 })
    records = append(records, std.kafka.message { timestamp_ms: 0 })
    extrema, extrema_error := std.kafka.encode_record_batch(records)
    if extrema_error.code != 0 || std.kafka.validate_record_batch(extrema).code != 0 { return 48 }
    println("Kafka RecordBatch valid-CRC structural mutations/truncation/int64 timestamps: PASS")
    return 0
}
