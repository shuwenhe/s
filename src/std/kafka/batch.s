package std.kafka

// Kafka magic-2, uncompressed, nontransactional records. At most 4096 records,
// 4096 headers per record and 1 MiB per batch. Timestamps are explicit epoch ms;
// zero is valid, negative values are rejected. Message offset/partition are ignored.
func _k_record_bytes(writer* w, nullable_bytes value) {
    size := -1
    if value.present { size = len(value.data) }
    put_varint(w*, size, 32)
    if value.present { put_raw(w*, value.data) }
}
func encode_record_batch(message[] records) (string, error) {
    if len(records) < 1 || len(records) > 4096 { return "", failure(error_invalid, "provide 1..4096 records") }
    base := records[0].timestamp_ms
    maximum := base
    if base < 0 { return "", failure(error_invalid, "negative record timestamp") }
    data := new_writer(1048515)
    i := 0
    while i < len(records) {
        record := records[i]
        if record.timestamp_ms < 0 { return "", failure(error_invalid, "negative record timestamp") }
        if len(record.headers) > 4096 { return "", failure(error_bounds, "too many record headers") }
        if record.timestamp_ms > maximum { maximum = record.timestamp_ms }
        body := new_writer(1048515)
        put_int(body*, 0, 1)
        put_varint(body*, record.timestamp_ms - base, 64)
        put_varint(body*, i, 32)
        _k_record_bytes(body*, record.key)
        _k_record_bytes(body*, record.value)
        header_count := len(record.headers)
        put_varint(body*, header_count, 32)
        j := 0
        while j < len(record.headers) && body.failure.code == 0 {
            h := record.headers[j]
            key_size := len(h.key)
            put_varint(body*, key_size, 32)
            put_raw(body*, h.key)
            _k_record_bytes(body*, h.value)
            j = j + 1
        }
        if body.failure.code != 0 { return "", body.failure }
        record_size := len(body.data)
        put_varint(data*, record_size, 32)
        put_raw(data*, body.data)
        if data.failure.code != 0 { return "", data.failure }
        i = i + 1
    }
    payload := new_writer(1048555)
    put_int(payload*, 0, 2)
    count := len(records)
    put_int(payload*, count - 1, 4)
    put_int(payload*, base, 8)
    put_int(payload*, maximum, 8)
    put_int(payload*, -1, 8)
    put_int(payload*, -1, 2)
    put_int(payload*, -1, 4)
    put_int(payload*, count, 4)
    put_raw(payload*, data.data)
    if payload.failure.code != 0 { return "", payload.failure }
    batch := new_writer(1048576)
    put_int(batch*, 0, 8)
    batch_size := len(payload.data) + 9
    put_int(batch*, batch_size, 4)
    put_int(batch*, -1, 4)
    put_int(batch*, 2, 1)
    checksum := crc32c(payload.data)
    put_int(batch*, checksum, 4)
    put_raw(batch*, payload.data)
    return batch.data, batch.failure
}

func _k_skip_record_bytes(cursor* c, bool nullable) {
    size := read_varint(c*, 32)
    if size == -1 && nullable { return }
    if size < 0 { _k_fail(c*, error_protocol, "invalid record field length"); return }
    take(c*, size)
    return
}

// Validate one producer-format batch, including CRC and every record boundary.
// This is a codec validator, not a Fetch/consumer API. Broker-assigned offsets,
// compression, transactions, idempotent batches and log-append-time are excluded.
func validate_record_batch(string data) error {
    c := new_cursor(data, 1048576)
    offset := read_int(c*, 8)
    size := read_int(c*, 4)
    epoch := read_int(c*, 4)
    magic := read_int(c*, 1)
    checksum := read_int(c*, 4) & 4294967295
    if c.failure.code != 0 { return c.failure }
    if size != len(data) - 12 || size < 49 || offset != 0 || epoch != -1 || magic != 2 {
        return failure(error_protocol, "invalid producer RecordBatch header")
    }
    payload_size := len(data) - 21
    payload := take(c*, payload_size)
    if checksum != crc32c(payload) { return failure(error_protocol, "RecordBatch CRC32C mismatch") }
    p := new_cursor(payload, 1048576)
    attributes := read_int(p*, 2)
    last := read_int(p*, 4)
    base := read_int(p*, 8)
    maximum := read_int(p*, 8)
    producer_id := read_int(p*, 8)
    producer_epoch := read_int(p*, 2)
    sequence := read_int(p*, 4)
    count := read_int(p*, 4)
    if p.failure.code != 0 { return p.failure }
    if attributes != 0 || producer_id != -1 || producer_epoch != -1 || sequence != -1 {
        return failure(error_unsupported, "unsupported RecordBatch attributes or producer state")
    }
    if count < 1 || count > 4096 || last != count - 1 || base < 0 || maximum < base {
        return failure(error_protocol, "invalid RecordBatch count or timestamps")
    }
    observed := base
    i := 0
    while i < count && p.failure.code == 0 {
        length := read_varint(p*, 32)
        body := take(p*, length)
        r := new_cursor(body, 1048576)
        attr := read_int(r*, 1)
        delta := read_varint(r*, 64)
        index := read_varint(r*, 32)
        // Avoid timestamp addition overflow before computing it.
        if delta < 0 - base || delta > 9223372036854775807 - base {
            return failure(error_protocol, "record timestamp overflow")
        }
        timestamp := base + delta
        if timestamp > observed { observed = timestamp }
        if attr != 0 || index != i || (i == 0 && delta != 0) { return failure(error_protocol, "invalid record attributes or offset delta") }
        _k_skip_record_bytes(r*, true)
        _k_skip_record_bytes(r*, true)
        headers := read_varint(r*, 32)
        if headers < 0 || headers > 4096 { return failure(error_protocol, "invalid record header count") }
        j := 0
        while j < headers && r.failure.code == 0 {
            _k_skip_record_bytes(r*, false)
            _k_skip_record_bytes(r*, true)
            j = j + 1
        }
        problem := finished(r*)
        if problem.code != 0 { return problem }
        i = i + 1
    }
    problem := finished(p*)
    if problem.code != 0 { return problem }
    if observed != maximum { return failure(error_protocol, "RecordBatch maximum timestamp mismatch") }
    return error {}
}
