package std.database.wire
import "std.database"

// Generic binary cursor, not a database protocol. Every error is sticky. A failed
// read leaves position unchanged. Callers must check code before trusting values.
struct cursor { string data, int position, int code }
extern "intrinsic" func __host_byte_at(string text, int index) int
extern "intrinsic" func __string_slice(string text, int start, int end) string
extern "intrinsic" func __std_byte_string(int byte) string
func available(cursor* source, int count) bool {
    if source.code != 0 { return false }
    if count < 0 || source.position < 0 || source.position > len(source.data) {
        source.code = std.database.error_protocol
        return false
    }
    // Subtraction avoids overflow for adversarial counts.
    if count > len(source.data) - source.position {
        source.code = std.database.error_protocol
        return false
    }
    return true
}
func read_byte(cursor* source) int {
    if !available(source*,1) { return 0 }
    number := __host_byte_at(source.data,source.position)
    source.position = source.position + 1
    return number
}
func read_bytes(cursor* source, int count) string {
    if !available(source*,count) { return "" }
    start := source.position
    source.position = source.position + count
    return __string_slice(source.data,start,source.position)
}
func read_cstring(cursor* source) string {
    if !available(source*,0) { return "" }
    end := source.position
    while end < len(source.data) {
        if __host_byte_at(source.data,end) == 0 {
            text := __string_slice(source.data,source.position,end)
            source.position = end + 1
            return text
        }
        end = end + 1
    }
    source.code = std.database.error_protocol
    return ""
}
func read_uint(cursor* source, int width, bool little_endian) int {
    if width < 1 || width > 8 { if source.code == 0 { source.code = std.database.error_invalid }
        return 0 }
    if !available(source*,width) { return 0 }
    number := 0
    index := 0
    while index < width {
        offset := index
        if little_endian { offset = width - index - 1 }
        byte := __host_byte_at(source.data,source.position + offset)
        if number > (9223372036854775807 - byte) / 256 {
            source.code = std.database.error_overflow
            return 0
        }
        number = number * 256 + byte
        index = index + 1
    }
    source.position = source.position + width
    return number
}
// Decimal arithmetic is bounded to <= 20 digits for an eight-byte integer.
func _decimal_step(string text, int byte) string {
    result := ""
    carry := byte
    index := len(text)
    while index > 0 {
        index = index - 1
        number := (__host_byte_at(text,index) - 48) * 256 + carry
        result = __std_byte_string(48 + number % 10) + result
        carry = number / 10
    }
    while carry > 0 {
        result = __std_byte_string(48 + carry % 10) + result
        carry = carry / 10
    }
    return result
}
func read_uint_decimal(cursor* source, int width, bool little_endian) string {
    if width < 1 || width > 8 { if source.code == 0 { source.code = std.database.error_invalid }
        return "" }
    if !available(source*,width) { return "" }
    text := "0"
    index := 0
    while index < width {
        offset := index
        if little_endian { offset = width - index - 1 }
        text = _decimal_step(text,__host_byte_at(source.data,source.position + offset))
        index = index + 1
    }
    source.position = source.position + width
    return text
}
func encode_uint(int number, int width, bool little_endian) (string,std.database.error) {
    if number < 0 || width < 1 || width > 8 {
        return "", std.database.failure(std.database.error_invalid,"invalid unsigned integer width or value")
    }
    remaining := number
    bytes := ""
    index := 0
    while index < width {
        byte := __std_byte_string(remaining % 256)
        if little_endian { bytes = bytes + byte } else { bytes = byte + bytes }
        remaining = remaining / 256
        index = index + 1
    }
    if remaining != 0 { return "", std.database.failure(std.database.error_overflow,"integer does not fit wire width") }
    return bytes, std.database.error { code: 0 }
}
