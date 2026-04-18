package compile.internal.typesys

use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.vec.Vec

func parse_type(string text) string {
    var clean = normalize_type_text(trim_text(text))
    if clean == "" {
        return "unknown"
    }
    if clean == "()" || clean == "never" || clean == "bool" || clean == "int32" || clean == "usize" || clean == "u8" || clean == "string" {
        return clean
    }
    if starts_with(clean, "&mut ") {
        return "&mut " + parse_type(slice(clean, 5, len(clean)))
    }
    if starts_with(clean, "&") {
        return "&" + parse_type(slice(clean, 1, len(clean)))
    }
    if starts_with(clean, "[]") {
        return "[]" + parse_type(slice(clean, 2, len(clean)))
    }
    return clean
}

func dump_type(string ty) string {
    return parse_type(ty)
}

func base_type_name(string ty) string {
    var clean = parse_type(ty)
    if starts_with(clean, "&mut ") {
        return base_type_name(slice(clean, 5, len(clean)))
    }
    if starts_with(clean, "&") {
        return base_type_name(slice(clean, 1, len(clean)))
    }
    if starts_with(clean, "[]") {
        return base_type_name(slice(clean, 2, len(clean)))
    }
    var bracket = find_char(clean, "[")
    if bracket >= 0 {
        return trim_text(slice(clean, 0, bracket))
    }
    var angle = find_char(clean, "<")
    if angle >= 0 {
        return trim_text(slice(clean, 0, angle))
    }
    var paren = find_char(clean, "(")
    if paren >= 0 {
        return trim_text(slice(clean, 0, paren))
    }
    return clean
}

func same_type(string left, string right) bool {
    return parse_type(left) == parse_type(right)
}

func is_builtin_primitive(string ty) bool {
    var clean = parse_type(ty)
    return clean == "()" || clean == "never" || clean == "bool" || clean == "int32" || clean == "usize" || clean == "u8" || clean == "string"
}

func is_copy_type(string ty) bool {
    var clean = parse_type(ty)
    if clean == "()" || clean == "never" || clean == "bool" || clean == "int32" || clean == "usize" || clean == "u8" {
        return true
    }
    if starts_with(clean, "&") {
        return true
    }
    return false
}

func is_reference_type(string ty) bool {
    return starts_with(trim_text(ty), "&")
}

func is_slice_type(string ty) bool {
    return starts_with(trim_text(ty), "[]")
}

func is_generic_type(string ty) bool {
    var clean = trim_text(ty)
    return find_char(clean, "[") >= 0 || find_char(clean, "<") >= 0
}

func normalize_type_text(string text) string {
    return trim_text(text)
}

func trim_text(string text) string {
    var start = 0
    var end = len(text)
    while start < end && is_space(char_at(text, start)) {
        start = start + 1
    }
    while end > start && is_space(char_at(text, end - 1)) {
        end = end - 1
    }
    return slice(text, start, end)
}

func starts_with(string text, string prefix) bool {
    var prefix_len = len(prefix)
    if prefix_len > len(text) {
        return false
    }
    return slice(text, 0, prefix_len) == prefix
}

func ends_with(string text, string suffix) bool {
    var suffix_len = len(suffix)
    var text_len = len(text)
    if suffix_len > text_len {
        return false
    }
    return slice(text, text_len - suffix_len, text_len) == suffix
}

func is_space(string ch) bool {
    return ch == " " || ch == "\n" || ch == "\t" || ch == "\r"
}

func find_char(string text, string needle) int32 {
    var i = 0
    while i < len(text) {
        if slice(text, i, i + 1) == needle {
            return i
        }
        i = i + 1
    }
    return 0 - 1
}

func extract_section(string text, string open, string close) string {
    var start = find_char(text, open)
    if start < 0 {
        return ""
    }
    var depth = 0
    var i = start
    while i < len(text) {
        var ch = slice(text, i, i + 1)
        if ch == open {
            depth = depth + 1
        } else if ch == close {
            depth = depth - 1
            if depth == 0 {
                return slice(text, start + 1, i)
            }
        }
        i = i + 1
    }
    return ""
}
