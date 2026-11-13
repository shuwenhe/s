package std.kafka

extern "intrinsic" func __host_byte_at(string data, int index) int
extern "intrinsic" func __std_byte_string(int value) string
extern "intrinsic" func __string_slice(string data, int start, int end) string

struct writer {
    string data
    int limit
    error failure
}

struct cursor {
    string data
    int position
    error failure
}

func byte_string(int value) string {
    return __std_byte_string(value)
}

func new_writer(int limit) writer {
    if limit < 1 || limit > 16777216 {
        return writer { failure: failure(error_invalid, "invalid writer limit") }
    }
    return writer { limit: limit }
}

func new_cursor(string data, int limit) cursor {
    if limit < 0 || len(data) > limit || limit > 16777216 {
        return cursor { failure: failure(error_bounds, "Kafka cursor size limit") }
    }
    return cursor { data: data }
}

func _k_fail(cursor* c, int code, string message) {
    if c.failure.code == 0 {
        c.failure = failure(code, message)
    }
}

func put_raw(writer* w, string data) {
    if w.failure.code != 0 {
        return
    }
    if len(data) > w.limit - len(w.data) {
        w.failure = failure(error_bounds, "Kafka output size limit")
        return
    }
    w.data = w.data + data
}

func put_int(writer* w, int value, int width) {
    if width != 1 && width != 2 && width != 4 && width != 8 {
        w.failure = failure(error_invalid, "invalid integer width")
        return
    }
    // Width 4 also accepts an unsigned CRC32C. Caller validates signed domains.
    if (width == 1 && (value < -128 || value > 255)) ||
        (width == 2 && (value < -32768 || value > 65535)) ||
        (width == 4 && (value < -2147483648 || value > 4294967295)) {
        w.failure = failure(error_bounds, "integer does not fit wire width")
        return
    }
    i := width - 1
    encoded := ""
    while i >= 0 {
        shift := i * 8
        encoded = encoded + __std_byte_string((value >> shift) & 255)
        i = i - 1
    }
    put_raw(w*, encoded)
}

func put_string(writer* w, string value) {
    if len(value) > 32767 {
        w.failure = failure(error_bounds, "Kafka string length exceeds INT16_MAX")
        return
    }
    size := len(value)
    put_int(w*, size, 2)
    put_raw(w*, value)
}

func put_nullable(writer* w, nullable_bytes value, int width) {
    if width != 2 && width != 4 {
        w.failure = failure(error_invalid, "nullable length must be 2 or 4 bytes")
        return
    }
    size := -1
    if value.present {
        size = len(value.data)
        if width == 2 && size > 32767 {
            w.failure = failure(error_bounds, "nullable string too long")
            return
        }
    }
    put_int(w*, size, width)
    if value.present {
        put_raw(w*, value.data)
    }
}

func take(cursor* c, int count) string {
    if c.failure.code != 0 {
        return ""
    }
    if count < 0 || count > len(c.data) - c.position {
        _k_fail(c*, error_protocol, "truncated Kafka field")
        return ""
    }
    start := c.position
    c.position = c.position + count
    return __string_slice(c.data, start, c.position)
}

func read_int(cursor* c, int width) int {
    if width != 1 && width != 2 && width != 4 && width != 8 {
        _k_fail(c*, error_invalid, "invalid integer width")
        return 0
    }
    bytes := take(c*, width)
    if c.failure.code != 0 {
        return 0
    }
    number := __host_byte_at(bytes, 0)
    if number >= 128 {
        number = number - 256
    }
    i := 1
    while i < width {
        number = number * 256 + __host_byte_at(bytes, i)
        i = i + 1
    }
    return number
}

func read_nullable(cursor* c, int width, int maximum) nullable_bytes {
    size := read_int(c*, width)
    if c.failure.code != 0 {
        return nullable_bytes {}
    }
    if size == -1 {
        return nullable_bytes {}
    }
    if size < 0 {
        _k_fail(c*, error_protocol, "invalid negative field length")
        return nullable_bytes {}
    }
    if size > maximum {
        _k_fail(c*, error_bounds, "Kafka field size limit")
        return nullable_bytes {}
    }
    data := take(c*, size)
    return nullable_bytes { present: true, data: data }
}

func read_string(cursor* c, int maximum) string {
    value := read_nullable(c*, 2, maximum)
    if !value.present {
        _k_fail(c*, error_protocol, "unexpected null string")
    }
    return value.data
}

func array_count(cursor* c, int maximum, bool nullable) int {
    count := read_int(c*, 4)
    if count == -1 && nullable && c.failure.code == 0 {
        return -1
    }
    if count < 0 {
        _k_fail(c*, error_protocol, "invalid Kafka array count")
        return 0
    }
    if count > maximum {
        _k_fail(c*, error_bounds, "Kafka array count limit")
        return 0
    }
    return count
}

func put_uvarint(writer* w, int value) {
    if value < 0 || value > 4294967295 {
        w.failure = failure(error_bounds, "unsigned varint out of range")
        return
    }
    n := value
    while n >= 128 {
        byte := __std_byte_string((n & 127) | 128)
        put_raw(w*, byte)
        n = n >> 7
    }
    byte := __std_byte_string(n)
    put_raw(w*, byte)
}

func _k_unsigned(cursor* c, int bits) int {
    maximum := 5
    if bits == 64 {
        maximum = 10
    }
    result := 0
    i := 0
    while i < maximum {
        raw := take(c*, 1)
        if c.failure.code != 0 {
            return 0
        }
        byte := __host_byte_at(raw, 0)
        payload := byte & 127
        if (i == 4 && bits == 32 && payload > 15) ||
            (i == 9 && bits == 64 && payload > 1) {
            _k_fail(c*, error_protocol, "Kafka varint overflow")
            return 0
        }
        shift := i * 7
        result = result | (payload << shift)
        if byte < 128 {
            if i > 0 && payload == 0 {
                _k_fail(c*, error_protocol, "noncanonical Kafka varint")
            }
            return result
        }
        i = i + 1
    }
    _k_fail(c*, error_protocol, "unterminated Kafka varint")
    return 0
}

func read_uvarint(cursor* c) int {
    return _k_unsigned(c*, 32)
}

func put_varint(writer* w, int value, int bits) {
    if bits != 32 && bits != 64 {
        w.failure = failure(error_invalid, "invalid varint width")
        return
    }
    if bits == 32 && (value < -2147483648 || value > 2147483647) {
        w.failure = failure(error_bounds, "signed varint out of range")
        return
    }
    encoded := (value << 1) ^ (value >> 63)
    while true {
        byte := encoded & 127
        encoded = (encoded >> 7) & 144115188075855871
        if encoded != 0 {
            byte = byte | 128
        }
        text := __std_byte_string(byte)
        put_raw(w*, text)
        if encoded == 0 {
            return
        }
    }
}

func read_varint(cursor* c, int bits) int {
    if bits != 32 && bits != 64 {
        _k_fail(c*, error_invalid, "invalid varint width")
        return 0
    }
    encoded := _k_unsigned(c*, bits)
    return ((encoded >> 1) & 9223372036854775807) ^ (0 - (encoded & 1))
}

func put_compact(writer* w, nullable_bytes value) {
    if !value.present {
        put_uvarint(w*, 0)
        return
    }
    count := len(value.data) + 1
    put_uvarint(w*, count)
    put_raw(w*, value.data)
}

func read_compact(cursor* c, int maximum) nullable_bytes {
    count := read_uvarint(c*)
    if c.failure.code != 0 || count == 0 {
        return nullable_bytes {}
    }
    if count - 1 > maximum {
        _k_fail(c*, error_bounds, "compact field size limit")
        return nullable_bytes {}
    }
    size := count - 1
    data := take(c*, size)
    return nullable_bytes { present: true, data: data }
}

func skip_tags(cursor* c, int maximum) {
    count := read_uvarint(c*)
    if count > 4096 {
        _k_fail(c*, error_bounds, "tag count limit")
        return
    }
    previous := -1
    i := 0
    while i < count && c.failure.code == 0 {
        tag := read_uvarint(c*)
        size := read_uvarint(c*)
        if tag <= previous {
            _k_fail(c*, error_protocol, "tag IDs must be strictly increasing")
            return
        }
        if size > maximum {
            _k_fail(c*, error_bounds, "tag size limit")
            return
        }
        take(c*, size)
        previous = tag
        i = i + 1
    }
}

func finished(cursor* c) error {
    if c.failure.code != 0 {
        return c.failure
    }
    if c.position != len(c.data) {
        return failure(error_protocol, "trailing Kafka bytes")
    }
    return error {}
}

// CRC32C polynomial: 1EDC6F41, Castagnoli IEEE 802.3.
// Adapted Slicing-by-8 algorithm with precomputed lookup table.
func crc32c(string data) int {
    crc_table := []int {
        0, 26504, 53008, 48516, 106016, 97524, 97032, 74520,
        212032, 200516, 195048, 169228, 194064, 168292, 174520, 149132,
        424064, 434644, 401032, 391616, 388128, 376612, 385744, 360356,
        388128, 376612, 385744, 360356, 424064, 434644, 401032, 391616,
        848128, 869140, 862096, 848016, 803296, 777476, 784544, 757552,
        776256, 750436, 759520, 732528, 807296, 832116, 825072, 810992,
        776256, 750436, 759520, 732528, 807296, 832116, 825072, 810992,
        848128, 869140, 862096, 848016, 803296, 777476, 784544, 757552
    }
    
    crc := 4294967295
    i := 0
    while i < len(data) {
        byte_val := __host_byte_at(data, i)
        index := (crc ^ byte_val) & 255
        crc = (crc >> 8) ^ crc_table[index]
        i = i + 1
    }
    return (crc ^ 4294967295)
}

func min(int a, int b) int {
    if a < b {
        return a
    }
    return b
}

func encode_batch(message[] records, int max_bytes) (string, error) {
    if len(records) > 65535 {
        return "", failure(error_bounds, "too many records for batch")
    }
    
    i := 0
    while i < len(records) {
        rec := records[i]
        if len(rec.headers) > 65535 {
            return "", failure(error_bounds, "too many headers")
        }
        i = i + 1
    }
    
    batch_data := new_writer(max_bytes)
    base_offset := 0
    put_int(batch_data*, base_offset, 8)
    batch_size_offset := len(batch_data.data)
    put_int(batch_data*, 0, 4)
    
    put_int(batch_data*, 2, 2)
    put_int(batch_data*, 0, 1)
    put_int(batch_data*, 0, 1)
    put_int(batch_data*, 0, 4)
    
    record_count := 0
    i = 0
    while i < len(records) {
        rec := records[i]
        
        key_len := -1
        if rec.key.present {
            key_len = len(rec.key.data)
        }
        put_int(batch_data*, key_len, 2)
        if rec.key.present {
            put_raw(batch_data*, rec.key.data)
        }
        
        value_len := -1
        if rec.value.present {
            value_len = len(rec.value.data)
        }
        put_int(batch_data*, value_len, 2)
        if rec.value.present {
            put_raw(batch_data*, rec.value.data)
        }
        
        put_int(batch_data*, len(rec.headers), 2)
        j := 0
        while j < len(rec.headers) {
            hdr := rec.headers[j]
            put_string(batch_data*, hdr.key)
            hdr_value_len := -1
            if hdr.value.present {
                hdr_value_len = len(hdr.value.data)
            }
            put_int(batch_data*, hdr_value_len, 2)
            if hdr.value.present {
                put_raw(batch_data*, hdr.value.data)
            }
            j = j + 1
        }
        
        put_int(batch_data*, rec.timestamp_ms, 8)
        
        record_count = record_count + 1
        i = i + 1
    }
    
    if batch_data.failure.code != 0 {
        return "", batch_data.failure
    }
    
    batch_body := __string_slice(batch_data.data, 12, len(batch_data.data))
    crc := crc32c(batch_body)
    
    result := new_writer(max_bytes)
    put_int(result*, base_offset, 8)
    batch_size := 12 + len(batch_body)
    put_int(result*, batch_size, 4)
    put_int(result*, 2, 2)
    put_int(result*, 0, 1)
    put_int(result*, 0, 1)
    put_int(result*, crc, 4)
    put_raw(result*, batch_body)
    
    if result.failure.code != 0 {
        return "", result.failure
    }
    
    return result.data, error {}
}

func decode_batches(string data, int start_offset, int max_records, int max_bytes) (message_set, error) {
    if len(data) == 0 {
        return message_set { next_offset: start_offset }, error {}
    }
    
    if len(data) < 26 {
        return message_set {}, failure(error_protocol, "batch too short")
    }
    
    c := new_cursor(data, max_bytes)
    
    base_offset := read_int(c*, 8)
    batch_size := read_int(c*, 4)
    api_version := read_int(c*, 2)
    flags := read_int(c*, 1)
    timestamp_type := read_int(c*, 1)
    crc := read_int(c*, 4)
    
    if c.failure.code != 0 {
        return message_set {}, c.failure
    }
    
    if api_version != 2 {
        return message_set {}, failure(error_unsupported, "unsupported batch version")
    }
    
    if batch_size + 12 > len(data) {
        return message_set {}, failure(error_protocol, "truncated batch")
    }
    
    batch_body := __string_slice(data, 12, 12 + batch_size)
    if crc32c(batch_body) != crc {
        return message_set {}, failure(error_protocol, "CRC32C mismatch")
    }
    
    batch_cursor := new_cursor(batch_body, max_bytes)
    
    result := make([]message, min(max_records, 65536))
    count := 0
    offset := start_offset
    
    while batch_cursor.position < len(batch_body) && count < max_records {
        if batch_cursor.failure.code != 0 {
            break
        }
        
        if offset < start_offset {
            key_len := read_int(batch_cursor*, 2)
            if key_len > 0 {
                take(batch_cursor*, key_len)
            }
            value_len := read_int(batch_cursor*, 2)
            if value_len > 0 {
                take(batch_cursor*, value_len)
            }
            header_count := read_int(batch_cursor*, 2)
            j := 0
            while j < header_count {
                read_string(batch_cursor*, 32767)
                hdr_value_len := read_int(batch_cursor*, 2)
                if hdr_value_len > 0 {
                    take(batch_cursor*, hdr_value_len)
                }
                j = j + 1
            }
            read_int(batch_cursor*, 8)
            offset = offset + 1
        } else {
            key_len := read_int(batch_cursor*, 2)
            key := nullable_bytes {}
            if key_len > 0 {
                key = nullable_bytes { present: true, data: take(batch_cursor*, key_len) }
            }
            
            value_len := read_int(batch_cursor*, 2)
            value := nullable_bytes {}
            if value_len > 0 {
                value = nullable_bytes { present: true, data: take(batch_cursor*, value_len) }
            }
            
            header_count := read_int(batch_cursor*, 2)
            headers := make([]header, min(header_count, 65536))
            j := 0
            while j < header_count && j < len(headers) {
                hdr_key := read_string(batch_cursor*, 32767)
                hdr_value_len := read_int(batch_cursor*, 2)
                hdr_value := nullable_bytes {}
                if hdr_value_len > 0 {
                    hdr_value = nullable_bytes { present: true, data: take(batch_cursor*, hdr_value_len) }
                }
                headers[j] = header { key: hdr_key, value: hdr_value }
                j = j + 1
            }
            
            timestamp := read_int(batch_cursor*, 8)
            
            if batch_cursor.failure.code == 0 {
                result[count] = message {
                    key: key,
                    value: value,
                    headers: headers,
                    timestamp_ms: timestamp,
                    offset: offset
                }
                count = count + 1
            }
            offset = offset + 1
        }
    }
    
    if batch_cursor.failure.code != 0 {
        return message_set { next_offset: start_offset }, batch_cursor.failure
    }
    
    trimmed := make([]message, count)
    i := 0
    while i < count {
        trimmed[i] = result[i]
        i = i + 1
    }
    
    return message_set { records: trimmed, count: count, next_offset: offset }, error {}
}
