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

// CRC32C checksum with reflected Castagnoli polynomial (0x82F63B78)
// Uses bit-by-bit computation since table literal is too large for IR operand
func crc32c(string data) int {
    // Polynomial: 0x82F63B78 = 2197175160
    poly := (33526 << 16) | 15224
    crc := 4294967295
    
    i := 0
    while i < len(data) {
        byte_val := __host_byte_at(data, i)
        crc = crc ^ byte_val
        
        j := 0
        while j < 8 {
            if (crc & 1) != 0 {
                crc = (crc >> 1) ^ poly
            } else {
                crc = crc >> 1
            }
            j = j + 1
        }
        
        i = i + 1
    }
    
    return (crc ^ 4294967295)
}
