package std.text
use std.conv.int_to_string as conv_int_to_string
use std.conv.int64_to_string as conv_int64_to_string
use std.conv.parse_int_default as conv_parse_int_default
use std.conv.float_to_string as conv_float_to_string
use std.conv.float_to_string_precision as conv_float_to_string_precision
use std.encoding.normalize_byte as encoding_normalize_byte
use std.encoding.is_ascii_space as encoding_is_ascii_space
use std.encoding.ascii_to_lower as encoding_ascii_to_lower
use std.encoding.is_ascii_printable as encoding_is_ascii_printable
use std.encoding.normalize_ascii_text as encoding_normalize_ascii_text
use std.encoding.bytes_to_string as encoding_bytes_to_string
use std.encoding.str_to_bytes as encoding_str_to_bytes
use std.encoding.bytes_to_string_range as encoding_bytes_to_string_range
func int_to_string(int value) string {
    conv_int_to_string(value)
}

func int64_to_string(int64 value) string {
    conv_int64_to_string(value)
}

func parse_int_default(string text, int fallback) int {
    conv_parse_int_default(text, fallback)
}

func float_to_string(float value) string {
    return conv_float_to_string(value
}

func float_to_string_precision(float value, int precision) string {
    return conv_float_to_string_precision(value, precision
}

func normalize_byte(int value) int {
    encoding_normalize_byte(value)
}

func is_ascii_space(int value) bool {
    encoding_is_ascii_space(value)
}

func ascii_to_lower(int value) int {
    encoding_ascii_to_lower(value)
}

func is_ascii_printable(int value) bool {
    encoding_is_ascii_printable(value)
}

func normalize_ascii_text(string text) string {
    encoding_normalize_ascii_text(text)
}

func bytes_to_string([]int bytes) string {
    encoding_bytes_to_string(bytes)
}

func str_to_bytes(string text) []int {
    encoding_str_to_bytes(text)
}

func bytes_to_string_range([]int bytes, int start, int length) string {
    encoding_bytes_to_string_range(bytes, start, length)
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
