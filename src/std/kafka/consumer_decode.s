package std.kafka

struct decoded_records {
    message[] records
    int next_offset
    bool partial_tail
}
// Consumer-only resumable decoder. Never expose output before stage=4.
struct consumer_decoder {
    cursor input
    cursor records
    decoded_records output
    error problem
    int stage
    int partition_id
    int requested_offset
    bool allow_partial_tail
    int complete_batches
    int previous_batch_end
    int base_offset
    int last_delta
    int base_timestamp
    int max_timestamp
    int attributes
    int count
    int index
    int previous_delta
    string crc_data
    int crc_position
    int crc_value
    int expected_crc
}
func consumer_decoder_new(string data, int partition_id, int offset, bool allow_partial_tail) consumer_decoder {
    d := consumer_decoder { input: new_cursor(data, 1048576), partition_id: partition_id, requested_offset: offset, stage: 1, allow_partial_tail: allow_partial_tail }
    d.output.next_offset = offset
    if partition_id < 0 || offset < 0 { d.problem = failure(error_invalid, "invalid consumer decode position") }
    if d.input.failure.code != 0 { d.problem = d.input.failure }
    return d
}
func _kc_decode_fail(consumer_decoder* d, error problem) {
    d.problem = problem
    d.output.records = message[]()
    d.output.next_offset = d.requested_offset
    d.stage = 4
}
func _kc_decode_error(consumer_decoder* d, int code, string text) {
    problem := failure(code, text)
    _kc_decode_fail(d*, problem)
}
func _kc_record_bytes(cursor* c, bool nullable) nullable_bytes {
    size := read_varint(c*, 32)
    if size == -1 && nullable { return nullable_bytes {} }
    if size < 0 { _k_fail(c*, error_protocol, "invalid record bytes length"); return nullable_bytes {} }
    value := take(c*, size)
    return nullable_bytes { present: true, data: value }
}
// One bounded step: batch header, 4096 CRC bytes, or at most 32 records.
func consumer_decoder_step(consumer_decoder* d) {
    if d.problem.code != 0 || d.stage == 4 { return }
    if d.stage == 1 {
        c := d.input
        remaining := len(c.data) - c.position
        if remaining == 0 { d.stage = 4; return }
        if remaining < 12 {
            if d.allow_partial_tail && d.complete_batches > 0 { d.output.partial_tail = true; d.stage = 4; return }
            _kc_decode_error(d*, error_protocol, "truncated batch header"); return
        }
        base := read_int(c*, 8)
        length := read_int(c*, 4)
        if d.complete_batches > 0 && base < d.previous_batch_end { _kc_decode_error(d*, error_protocol, "overlapping or unordered record batches"); return }
        if base < 0 || length < 49 { _kc_decode_error(d*, error_protocol, "invalid batch offset or length"); return }
        if length > 1048564 { _kc_decode_error(d*, error_bounds, "batch exceeds consumer frame cap"); return }
        if length > remaining - 12 {
            if d.allow_partial_tail && d.complete_batches > 0 { d.output.partial_tail = true; d.stage = 4; return }
            _kc_decode_error(d*, error_protocol, "truncated batch body"); return
        }
        raw := take(c*, length)
        h := new_cursor(raw, 1048576)
        epoch := read_int(h*, 4)
        magic := read_int(h*, 1)
        checksum := read_int(h*, 4) & 4294967295
        payload_size := length - 9
        payload := take(h*, payload_size)
        if epoch < -1 || magic != 2 || h.failure.code != 0 { _kc_decode_error(d*, error_protocol, "invalid magic-2 batch header"); return }
        d.input = c
        d.base_offset = base
        d.expected_crc = checksum
        d.crc_data = payload
        d.crc_value = 4294967295
        d.crc_position = 0
        d.stage = 2
        return
    }
    if d.stage == 2 {
        crc := d.crc_value
        position := d.crc_position
        limit := position + 4096
        if limit > len(d.crc_data) { limit = len(d.crc_data) }
        while position < limit {
            crc = crc ^ __host_byte_at(d.crc_data, position)
            bit := 0
            while bit < 8 {
                if (crc & 1) != 0 { crc = (crc >> 1) ^ 2197175160 } else { crc = crc >> 1 }
                bit = bit + 1
            }
            position = position + 1
        }
        d.crc_value = crc
        d.crc_position = position
        if position < len(d.crc_data) { return }
        if (crc ^ 4294967295) != d.expected_crc { _kc_decode_error(d*, error_protocol, "consumer RecordBatch CRC32C mismatch"); return }
        p := new_cursor(d.crc_data, 1048576)
        attr := read_int(p*, 2)
        last := read_int(p*, 4)
        base_time := read_int(p*, 8)
        max_time := read_int(p*, 8)
        producer_id := read_int(p*, 8)
        producer_epoch := read_int(p*, 2)
        sequence := read_int(p*, 4)
        count := read_int(p*, 4)
        if p.failure.code != 0 { _kc_decode_fail(d*, p.failure); return }
        if (attr & 7) != 0 { _kc_decode_error(d*, error_unsupported, "consumer compression codec unsupported"); return }
        if attr < 0 || (attr & 65408) != 0 { _kc_decode_error(d*, error_unsupported, "consumer batch attributes unsupported"); return }
        if last < 0 || count < 0 || count > 4096 || d.base_offset > 9223372036854775806 - last || base_time < -1 || max_time < -1 {
            _kc_decode_error(d*, error_protocol, "invalid batch count/offset/timestamp"); return
        }
        if producer_id < -1 || producer_epoch < -1 || sequence < -1 ||
            (producer_id == -1 && (producer_epoch != -1 || sequence != -1)) ||
            (producer_id >= 0 && producer_epoch < 0) {
            _kc_decode_error(d*, error_protocol, "invalid batch producer metadata"); return
        }
        if (attr & 32) != 0 && (count != 1 || producer_id < 0 || producer_epoch < 0) {
            _kc_decode_error(d*, error_protocol, "invalid control batch metadata"); return
        }
        d.attributes = attr
        d.last_delta = last
        d.base_timestamp = base_time
        d.max_timestamp = max_time
        d.count = count
        d.index = 0
        d.previous_delta = -1
        d.records = p
        d.stage = 3
        return
    }
    if d.stage == 3 {
        p := d.records
        work := 0
        while d.index < d.count && work < 32 {
            size := read_varint(p*, 32)
            body := take(p*, size)
            r := new_cursor(body, 1048576)
            attr := read_int(r*, 1)
            time_delta := read_varint(r*, 64)
            offset_delta := read_varint(r*, 32)
            if attr != 0 || offset_delta < 0 || offset_delta <= d.previous_delta || offset_delta > d.last_delta {
                _kc_decode_error(d*, error_protocol, "invalid consumer record offset/attributes"); return
            }
            timestamp := d.max_timestamp
            if (d.attributes & 8) == 0 {
                if (time_delta > 0 && d.base_timestamp > 9223372036854775807 - time_delta) ||
                    (time_delta < 0 && d.base_timestamp < -9223372036854775807 - 1 - time_delta) {
                    _kc_decode_error(d*, error_protocol, "record timestamp overflow"); return
                }
                timestamp = d.base_timestamp + time_delta
                if timestamp < -1 || timestamp > d.max_timestamp { _kc_decode_error(d*, error_protocol, "invalid record timestamp"); return }
            }
            key := _kc_record_bytes(r*, true)
            value := _kc_record_bytes(r*, true)
            header_count := read_varint(r*, 32)
            if header_count < 0 || header_count > 4096 { _kc_decode_error(d*, error_bounds, "consumer record header count"); return }
            headers := header[]()
            j := 0
            while j < header_count && r.failure.code == 0 {
                name := _kc_record_bytes(r*, false)
                field := _kc_record_bytes(r*, true)
                if !_kc_header_utf8(name.data) { invalid_header := failure(error_protocol, "invalid UTF-8 header key"); _kc_decode_fail(d*, invalid_header); return }
                headers = append(headers, header { key: name.data, value: field })
                j = j + 1
            }
            problem := finished(r*)
            if problem.code != 0 { _kc_decode_fail(d*, problem); return }
            if p.failure.code != 0 { _kc_decode_fail(d*, p.failure); return }
            if (d.attributes & 32) != 0 {
                if !key.present || !value.present || len(key.data) != 4 || len(value.data) != 6 || header_count != 0 {
                    _kc_decode_error(d*, error_protocol, "invalid transaction control marker"); return
                }
                key_cursor := new_cursor(key.data, 4)
                key_version := read_int(key_cursor*, 2)
                marker_type := read_int(key_cursor*, 2)
                value_cursor := new_cursor(value.data, 6)
                value_version := read_int(value_cursor*, 2)
                coordinator_epoch := read_int(value_cursor*, 4)
                if key_version != 0 || marker_type < 0 || marker_type > 1 || value_version != 0 || coordinator_epoch < 0 {
                    _kc_decode_error(d*, error_protocol, "unknown transaction control marker"); return
                }
            }
            offset := d.base_offset + offset_delta
            if offset >= d.requested_offset && (d.attributes & 32) == 0 {
                if len(d.output.records) >= 4096 { _kc_decode_error(d*, error_bounds, "consumer decoded record count"); return }
                record := message { key: key, value: value, headers: headers, timestamp_ms: timestamp, offset: offset, partition: d.partition_id }
                d.output.records = append(d.output.records, record)
            }
            d.previous_delta = offset_delta
            d.index = d.index + 1
            work = work + 1
        }
        d.records = p
        if d.index < d.count { return }
        problem := finished(p*)
        if problem.code != 0 { _kc_decode_fail(d*, problem); return }
        next := d.base_offset + d.last_delta + 1
        if next > d.output.next_offset { d.output.next_offset = next }
        d.previous_batch_end = next
        d.complete_batches = d.complete_batches + 1
        d.crc_data = ""
        d.records = cursor {}
        d.stage = 1
    }
}
// Strict standalone decoder. Fetch framing may opt in to reported partial tails.
func decode_record_batches(string data, int partition_id, int offset) (decoded_records, error) {
    d := consumer_decoder_new(data, partition_id, offset, false)
    while d.stage != 4 && d.problem.code == 0 { consumer_decoder_step(d*) }
    if d.problem.code != 0 { return decoded_records { next_offset: offset }, d.problem }
    return d.output, error {}
}

func _kc_header_utf8(string data) bool {
    i := 0
    while i < len(data) {
        first := __host_byte_at(data, i)
        count := 0
        code := 0
        minimum := 0
        if first < 128 { i = i + 1; continue }
        if first >= 194 && first <= 223 { count = 1; code = first & 31; minimum = 128 }
        else if first >= 224 && first <= 239 { count = 2; code = first & 15; minimum = 2048 }
        else if first >= 240 && first <= 244 { count = 3; code = first & 7; minimum = 65536 }
        else { return false }
        if i + count >= len(data) { return false }
        j := 1
        while j <= count {
            next := __host_byte_at(data, i + j)
            if next < 128 || next > 191 { return false }
            code = code * 64 + (next & 63)
            j = j + 1
        }
        if code < minimum || code > 1114111 || (code >= 55296 && code <= 57343) { return false }
        i = i + count + 1
    }
    return true
}
