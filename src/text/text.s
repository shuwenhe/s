package std.text
import (
    "std.conv"
    "std.encoding"
)
func int_to_string(int value) string {
    std.conv.int_to_string(value)
}

func int64_to_string(int64 value) string {
    std.conv.int64_to_string(value)
}

func parse_int_default(string text, int fallback) int {
    std.conv.parse_int_default(text, fallback)
}

func float_to_string(float value) string {
    return std.conv.float_to_string(value
}

func float_to_string_precision(float value, int precision) string {
    return std.conv.float_to_string_precision(value, precision
}

func normalize_byte(int value) int {
    std.encoding.normalize_byte(value)
}

func is_ascii_space(int value) bool {
    std.encoding.is_ascii_space(value)
}

func ascii_to_lower(int value) int {
    std.encoding.ascii_to_lower(value)
}

func is_ascii_printable(int value) bool {
    std.encoding.is_ascii_printable(value)
}

func normalize_ascii_text(string text) string {
    std.encoding.normalize_ascii_text(text)
}

func bytes_to_string(int[] bytes) string {
    std.encoding.bytes_to_string(bytes)
}

func str_to_bytes(string text) int[] {
    std.encoding.str_to_bytes(text)
}

func bytes_to_string_range(int[] bytes, int start, int length) string {
    std.encoding.bytes_to_string_range(bytes, start, length)
}

func substring(string s, int start, int end) string {
    if start < 0 || end > len(s) || start > end {
        return ""
    }
    string result = ""
    int i = start
    for i < end {
        result = result + string(s[i])
        i = i + 1
    }
    return result
}

func find_substring(string text, string substr) int {
    if len(substr) == 0 || len(substr) > len(text) {
        return -1
    }
    int i = 0
    for i <= len(text) - len(substr) {
        bool matches = true
        int j = 0
        for j < len(substr) {
            if text[i + j] != substr[j] {
                matches = false
                break
            }
            j = j + 1
        }
        if matches {
            return i
        }
        i = i + 1
    }
    return -1
}
