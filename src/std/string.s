package std.string
import ("std.result"; "std.prelude")

struct string_error { int code }
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
func prefix_table(string needle) int[] {
    table := int[]()
    index := 0
    while index < len(needle) { table = append(table, 0); index = index + 1 }
    index = 1
    matched := 0
    while index < len(needle) {
        byte := __host_byte_at(needle, index)
        while matched > 0 && byte != __host_byte_at(needle, matched) { matched = table[matched - 1] }
        if byte == __host_byte_at(needle, matched) { matched = matched + 1 }
        table[index] = matched
        index = index + 1
    }
    return table
}
func search(string text, string needle, int start, int[] table) int {
    if len(needle) == 0 { return start }
    index := start
    matched := 0
    while index < len(text) {
        byte := __host_byte_at(text, index)
        while matched > 0 && byte != __host_byte_at(needle, matched) { matched = table[matched - 1] }
        if byte == __host_byte_at(needle, matched) { matched = matched + 1 }
        if matched == len(needle) { return index - len(needle) + 1 }
        index = index + 1
    }
    return -1
}
func find_from(string text, string needle, int start) (int, string_error) {
    if start < 0 || start > len(text) { return -1, string_error { code: 22 } }
    table := prefix_table(needle)
    return search(text, needle, start, table), string_error { code: 0 }
}
func index_of(string text, string needle) int {
    table := prefix_table(needle)
    return search(text, needle, 0, table)
}
func contains(string text, string needle) bool { return index_of(text, needle) >= 0 }
func starts_with(string text, string prefix) bool {
    if len(prefix) > len(text) { return false }
    return std.prelude.prelude_slice(text, 0, len(prefix)) == prefix
}
func ends_with(string text, string suffix) bool {
    if len(suffix) > len(text) { return false }
    return std.prelude.prelude_slice(text, len(text) - len(suffix), len(text)) == suffix
}
func split(string text, string separator) (string[], string_error) {
    fields := string[]()
    if len(separator) == 0 { return fields, string_error { code: 22 } }
    table := prefix_table(separator)
    start := 0
    while true {
        found := search(text, separator, start, table)
        if found < 0 { break }
        fields = append(fields, std.prelude.prelude_slice(text, start, found))
        start = found + len(separator)
    }
    fields = append(fields, std.prelude.prelude_slice(text, start, len(text)))
    return fields, string_error { code: 0 }
}
func join_range(string[] fields, string separator, int start, int end) string {
    if start == end { return "" }
    if end - start == 1 { return fields[start] }
    middle := start + (end - start) / 2
    left := join_range(fields, separator, start, middle)
    right := join_range(fields, separator, middle, end)
    return left + separator + right
}
func join(string[] fields, string separator) string { return join_range(fields, separator, 0, len(fields)) }
func replace(string text, string old, string replacement) (string, string_error) {
    fields, error := split(text, old)
    if error.code != 0 { return "", error }
    return join(fields, replacement), string_error { code: 0 }
}
func ascii_space(int byte) bool { return byte == 32 || (byte >= 9 && byte <= 13) }
func trim_ascii(string text) string {
    start := 0
    end := len(text)
    while start < end && ascii_space(__host_byte_at(text, start)) { start = start + 1 }
    while end > start && ascii_space(__host_byte_at(text, end - 1)) { end = end - 1 }
    return std.prelude.prelude_slice(text, start, end)
}
func change_ascii_case(string text, bool upper) string {
    chunks := string[]()
    chunk := ""
    index := 0
    while index < len(text) {
        byte := __host_byte_at(text, index)
        if upper && byte >= 97 && byte <= 122 { byte = byte - 32 }
        if !upper && byte >= 65 && byte <= 90 { byte = byte + 32 }
        chunk = chunk + __std_byte_string(byte)
        if len(chunk) == 64 { chunks = append(chunks, chunk); chunk = "" }
        index = index + 1
    }
    if len(chunk) > 0 { chunks = append(chunks, chunk) }
    return join(chunks, "")
}
func lower_ascii(string text) string { return change_ascii_case(text, false) }
func upper_ascii(string text) string { return change_ascii_case(text, true) }
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
