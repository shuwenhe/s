package std.string
import ("std.result"; "std.prelude")

struct string_error { int code }
extern "intrinsic" func __std_string_array_concat(string[] left, string[] right) string[]
extern "intrinsic" func __host_byte_at(string text, int index) int
extern "intrinsic" func __std_byte_string(int value) string

func byte_at(string text, int index) (int, string_error) {
    if index < 0 || index >= len(text) { return 0, string_error { code: 22 } }
    return __host_byte_at(text, index), string_error { code: 0 }
}
func from_byte(int value) (string, string_error) {
    if value < 0 || value > 255 { return "", string_error { code: 22 } }
    return __std_byte_string(value), string_error { code: 0 }
}
func slice(string text, int start, int end) (string, string_error) {
    if start < 0 || end < start || end > len(text) { return "", string_error { code: 22 } }
    return std.prelude.prelude_slice(text, start, end), string_error { code: 0 }
}
func compare(string left, string right) int {
    index := 0
    while index < len(left) && index < len(right) {
        a := __host_byte_at(left, index)
        b := __host_byte_at(right, index)
        if a < b { return -1 }
        if a > b { return 1 }
        index = index + 1
    }
    if len(left) < len(right) { return -1 }
    if len(left) > len(right) { return 1 }
    return 0
}
// Critical factorization for Two-Way search: constant auxiliary space.
struct _factorization { int suffix, int period }
func _maximal_suffix(string needle, bool reverse) _factorization {
    suffix := -1
    candidate := 0
    offset := 1
    period := 1
    while candidate + offset < len(needle) {
        a := __host_byte_at(needle, candidate + offset)
        b := __host_byte_at(needle, suffix + offset)
        less := a < b
        if reverse { less = a > b }
        if less {
            candidate = candidate + offset
            offset = 1
            period = candidate - suffix
        } else {
            if a == b {
                if offset != period { offset = offset + 1 } else { candidate = candidate + period; offset = 1 }
            } else {
                suffix = candidate
                candidate = suffix + 1
                offset = 1
                period = 1
            }
        }
    }
    return _factorization { suffix: suffix, period: period }
}
func _search(string text, string needle, int start) int {
    size := len(needle)
    if size == 0 { return start }
    if size > len(text) - start { return -1 }
    factor := _maximal_suffix(needle, false)
    reverse := _maximal_suffix(needle, true)
    if reverse.suffix > factor.suffix { factor = reverse }
    suffix := factor.suffix
    period := factor.period
    periodic := true
    index := 0
    while index <= suffix {
        if __host_byte_at(needle, index) != __host_byte_at(needle, index + period) { periodic = false; break }
        index = index + 1
    }
    remembered := 0
    if periodic { remembered = size - period } else {
        period = suffix
        if size - suffix - 1 > period { period = size - suffix - 1 }
        period = period + 1
    }
    memory := 0
    position := start
    while position <= len(text) - size {
        index = suffix + 1
        if memory > index { index = memory }
        while index < size && __host_byte_at(needle, index) == __host_byte_at(text, position + index) { index = index + 1 }
        if index < size {
            position = position + index - suffix
            memory = 0
        } else {
            index = suffix + 1
            while index > memory && __host_byte_at(needle, index - 1) == __host_byte_at(text, position + index - 1) { index = index - 1 }
            if index <= memory { return position }
            position = position + period
            memory = remembered
        }
    }
    return -1
}
func find_from(string text, string needle, int start) (int, string_error) {
    if start < 0 || start > len(text) { return -1, string_error { code: 22 } }
    return _search(text, needle, start), string_error { code: 0 }
}
func index_of(string text, string needle) int { return _search(text, needle, 0) }
func contains(string text, string needle) bool { return index_of(text, needle) >= 0 }
func starts_with(string text, string prefix) bool {
    if len(prefix) > len(text) { return false }
    return std.prelude.prelude_slice(text, 0, len(prefix)) == prefix
}
func ends_with(string text, string suffix) bool {
    if len(suffix) > len(text) { return false }
    return std.prelude.prelude_slice(text, len(text) - len(suffix), len(text)) == suffix
}
struct _split_piece { string[] fields, int next }
func _split_fields(string text, string separator, int start, int count) _split_piece {
    if count == 1 {
        end := _search(text, separator, start)
        next := len(text)
        if end < 0 { end = len(text) } else { next = end + len(separator) }
        field := std.prelude.prelude_slice(text, start, end)
        return _split_piece { fields: string[]{field}, next: next }
    }
    left := _split_fields(text, separator, start, count / 2)
    right := _split_fields(text, separator, left.next, count - count / 2)
    return _split_piece { fields: __std_string_array_concat(left.fields, right.fields), next: right.next }
}
func split(string text, string separator) (string[], string_error) {
    if len(separator) == 0 { return string[](), string_error { code: 22 } }
    count := 1
    start := 0
    while true {
        found := _search(text, separator, start)
        if found < 0 { break }
        count = count + 1
        start = found + len(separator)
    }
    piece := _split_fields(text, separator, 0, count)
    return piece.fields, string_error { code: 0 }
}
func _join_range(string[] fields, string separator, int start, int end) string {
    if start == end { return "" }
    if end - start == 1 { return fields[start] }
    middle := start + (end - start) / 2
    left := _join_range(fields, separator, start, middle)
    right := _join_range(fields, separator, middle, end)
    return left + separator + right
}
func join(string[] fields, string separator) string { return _join_range(fields, separator, 0, len(fields)) }
func replace(string text, string old, string replacement) (string, string_error) {
    fields, error := split(text, old)
    if error.code != 0 { return "", error }
    return join(fields, replacement), string_error { code: 0 }
}
func _ascii_space(int byte) bool { return byte == 32 || (byte >= 9 && byte <= 13) }
func trim_ascii(string text) string {
    start := 0
    end := len(text)
    while start < end && _ascii_space(__host_byte_at(text, start)) { start = start + 1 }
    while end > start && _ascii_space(__host_byte_at(text, end - 1)) { end = end - 1 }
    return std.prelude.prelude_slice(text, start, end)
}
func _change_ascii_case(string text, bool upper, int start, int end) string {
    if end - start > 64 {
        middle := start + (end - start) / 2
        left := _change_ascii_case(text, upper, start, middle)
        right := _change_ascii_case(text, upper, middle, end)
        return left + right
    }
    chunk := ""
    index := start
    while index < end {
        byte := __host_byte_at(text, index)
        if upper && byte >= 97 && byte <= 122 { byte = byte - 32 }
        if !upper && byte >= 65 && byte <= 90 { byte = byte + 32 }
        chunk = chunk + __std_byte_string(byte)
        index = index + 1
    }
    return chunk
}
func lower_ascii(string text) string { return _change_ascii_case(text, false, 0, len(text)) }
func upper_ascii(string text) string { return _change_ascii_case(text, true, 0, len(text)) }
func format_int(int value) string { return std.prelude.to_string(value) }
func parse_int(string text) (int, string_error) {
    if len(text) == 0 { return 0, string_error { code: 22 } }
    index := 0
    negative := false
    first := __host_byte_at(text, 0)
    if first == 45 || first == 43 { negative = first == 45; index = 1 }
    if index == len(text) { return 0, string_error { code: 22 } }
    // Accumulate negatively so INT64_MIN is representable throughout.
    limit := -9223372036854775807
    if negative { limit = -9223372036854775808 }
    value := 0
    while index < len(text) {
        byte := __host_byte_at(text, index)
        if byte < 48 || byte > 57 { return 0, string_error { code: 22 } }
        digit := byte - 48
        if value < limit / 10 { return 0, string_error { code: 34 } }
        value = value * 10
        if value < limit + digit { return 0, string_error { code: 34 } }
        value = value - digit
        index = index + 1
    }
    if !negative { value = 0 - value }
    return value, string_error { code: 0 }
}
