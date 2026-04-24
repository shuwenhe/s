package compile.internal.typesys

use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.vec.vec

struct type_ref {
    string canonical
    string base
    bool is_ref
    bool is_mut_ref
    bool is_slice
    vec[string] args
}

func parse_type(string text) string {
    var clean = normalize_type_text(trim_text(text))
    if clean == "" {
        return "unknown"
    }
    if is_builtin_primitive(clean) {
        return clean
    }
    if starts_with(clean, "&mut ") {
        return "&mut " + parse_type(slice(clean, 5, clean.len()))
    }
    if starts_with(clean, "&") {
        return "&" + parse_type(slice(clean, 1, clean.len()))
    }
    if starts_with(clean, "[]") {
        return "[]" + parse_type(slice(clean, 2, clean.len()))
    }
    return clean
}

func parse_type_ref(string text) type_ref {
    var canonical = parse_type(text)
    var rest = canonical
    var is_ref = false
    var is_mut_ref = false
    var is_slice = false

    if starts_with(rest, "&mut ") {
        is_ref = true
        is_mut_ref = true
        rest = parse_type(slice(rest, 5, rest.len()))
    } else if starts_with(rest, "&") {
        is_ref = true
        rest = parse_type(slice(rest, 1, rest.len()))
    }

    if starts_with(rest, "[]") {
        is_slice = true
        rest = parse_type(slice(rest, 2, rest.len()))
    }

    type_ref {
        canonical: canonical,
        base: base_type_name(rest),
        is_ref: is_ref,
        is_mut_ref: is_mut_ref,
        is_slice: is_slice,
        args: extract_type_args(canonical),
    }
}

func dump_type_ref(type_ref ty) string {
    ty.canonical
}

func same_type_ref(type_ref left, type_ref right) bool {
    left.canonical == right.canonical
}

func type_arg(type_ref ty, int32 index) string {
    if index < 0 || index >= ty.args.len() {
        return "unknown"
    }
    parse_type(ty.args[index])
}

func generic_arity(string ty) int32 {
    var args = extract_type_args(ty)
    args.len()
}

func has_unknown_component(string ty) bool {
    var clean = parse_type(ty)
    if clean == "unknown" {
        return true
    }
    var args = extract_type_args(clean)
    var i = 0
    while i < args.len() {
        if parse_type(args[i]) == "unknown" {
            return true
        }
        i = i + 1
    }
    false
}

func rules_consistent() bool {
    if parse_type("  int32  ") != "int32" {
        return false
    }
    if !same_type("[]int32", "[]int32") {
        return false
    }

    var result_ref = parse_type_ref("result[int32, string]")
    if result_ref.base != "result" {
        return false
    }
    if type_arg(result_ref, 0) != "int32" {
        return false
    }
    if type_arg(result_ref, 1) != "string" {
        return false
    }
    if generic_arity("result[int32, string]") != 2 {
        return false
    }

    var ref_ref = parse_type_ref("&mut []int32")
    if !ref_ref.is_ref || !ref_ref.is_mut_ref {
        return false
    }
    true
}

func dump_type(string ty) string {
    return parse_type(ty)
}

func base_type_name(string ty) string {
    var clean = parse_type(ty)
    if starts_with(clean, "&mut ") {
        return base_type_name(slice(clean, 5, clean.len()))
    }
    if starts_with(clean, "&") {
        return base_type_name(slice(clean, 1, clean.len()))
    }
    if starts_with(clean, "[]") {
        return base_type_name(slice(clean, 2, clean.len()))
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

func extract_type_args(string type_name) vec[string] {
    var out = vec[string]()
    var clean = parse_type(type_name)
    var open = find_char(clean, "[")
    var close = find_last_char(clean, "]")
    if open < 0 || close <= open + 1 {
        return out
    }

    var inner = slice(clean, open + 1, close)
    var depth = 0
    var start = 0
    var i = 0
    while i < inner.len() {
        var ch = char_at(inner, i)
        if ch == "[" {
            depth = depth + 1
        } else if ch == "]" {
            depth = depth - 1
        } else if ch == "," && depth == 0 {
            out.push(trim_text(slice(inner, start, i)))
            start = i + 1
        }
        i = i + 1
    }

    if start < inner.len() {
        out.push(trim_text(slice(inner, start, inner.len())))
    }
    out
}

func same_type(string left, string right) bool {
    return parse_type(left) == parse_type(right)
}

func compatible_type(string left, string right) bool {
    var l = parse_type(left)
    var r = parse_type(right)

    if l == r {
        return true
    }
    if l == "unknown" || r == "unknown" {
        return false
    }

    if is_tuple_type(l) || is_tuple_type(r) {
        return compatible_tuple_type(l, r)
    }

    var lt = parse_type_ref(l)
    var rt = parse_type_ref(r)

    if lt.is_ref != rt.is_ref || lt.is_mut_ref != rt.is_mut_ref || lt.is_slice != rt.is_slice {
        return false
    }
    if lt.base != rt.base {
        return false
    }
    if lt.args.len() != rt.args.len() {
        return false
    }

    var i = 0
    while i < lt.args.len() {
        if !compatible_type(lt.args[i], rt.args[i]) {
            return false
        }
        i = i + 1
    }
    true
}

func comparable_type(string ty) bool {
    var clean = parse_type(ty)
    if clean == "unknown" || clean == "map" || clean == "fn" {
        return false
    }

    if is_builtin_primitive(clean) {
        return true
    }
    if starts_with(clean, "&") {
        return true
    }
    if starts_with(clean, "[]") {
        return false
    }

    if is_tuple_type(clean) {
        var items = extract_tuple_args(clean)
        var i = 0
        while i < items.len() {
            if !comparable_type(items[i]) {
                return false
            }
            i = i + 1
        }
        return true
    }

    var base = base_type_name(clean)
    if base == "option" || base == "result" {
        var args = extract_type_args(clean)
        var i = 0
        while i < args.len() {
            if !comparable_type(args[i]) {
                return false
            }
            i = i + 1
        }
        return true
    }

    false
}

func assignable_type(string target, string source) bool {
    var t = parse_type(target)
    var s = parse_type(source)
    if t == s {
        return true
    }
    if t == "unknown" || s == "unknown" {
        return false
    }

    if compatible_type(t, s) {
        return true
    }

    if is_numeric_primitive(t) && is_numeric_primitive(s) {
        return numeric_rank(t) >= numeric_rank(s)
    }

    if is_tuple_type(t) || is_tuple_type(s) {
        return assignable_tuple_type(t, s)
    }

    false
}

func compatible_tuple_type(string left, string right) bool {
    var l = parse_type(left)
    var r = parse_type(right)
    if !is_tuple_type(l) || !is_tuple_type(r) {
        return false
    }

    var la = extract_tuple_args(l)
    var ra = extract_tuple_args(r)
    if la.len() != ra.len() {
        return false
    }

    var i = 0
    while i < la.len() {
        if !compatible_type(la[i], ra[i]) {
            return false
        }
        i = i + 1
    }
    true
}

func assignable_tuple_type(string target, string source) bool {
    var t = parse_type(target)
    var s = parse_type(source)
    if !is_tuple_type(t) || !is_tuple_type(s) {
        return false
    }

    var ta = extract_tuple_args(t)
    var sa = extract_tuple_args(s)
    if ta.len() != sa.len() {
        return false
    }

    var i = 0
    while i < ta.len() {
        if !assignable_type(ta[i], sa[i]) {
            return false
        }
        i = i + 1
    }
    true
}

func is_tuple_type(string ty) bool {
    var clean = parse_type(ty)
    if clean.len() < 2 {
        return false
    }
    return starts_with(clean, "(") && ends_with(clean, ")")
}

func extract_tuple_args(string type_name) vec[string] {
    var out = vec[string]()
    var clean = parse_type(type_name)
    if !is_tuple_type(clean) {
        return out
    }

    var inner = slice(clean, 1, clean.len() - 1)
    var depth = 0
    var start = 0
    var i = 0
    while i < inner.len() {
        var ch = char_at(inner, i)
        if ch == "(" || ch == "[" {
            depth = depth + 1
        } else if ch == ")" || ch == "]" {
            depth = depth - 1
        } else if ch == "," && depth == 0 {
            out.push(trim_text(slice(inner, start, i)))
            start = i + 1
        }
        i = i + 1
    }
    if start < inner.len() {
        out.push(trim_text(slice(inner, start, inner.len())))
    }
    out
}

func is_numeric_primitive(string ty) bool {
    var clean = parse_type(ty)
    return clean == "i8"
        || clean == "i16"
        || clean == "int32"
        || clean == "i64"
        || clean == "isize"
        || clean == "u8"
        || clean == "u16"
        || clean == "u32"
        || clean == "u64"
        || clean == "usize"
        || clean == "f32"
        || clean == "f64"
}

func numeric_rank(string ty) int32 {
    var clean = parse_type(ty)
    if clean == "i8" || clean == "u8" {
        return 1
    }
    if clean == "i16" || clean == "u16" {
        return 2
    }
    if clean == "int32" || clean == "u32" || clean == "f32" {
        return 3
    }
    if clean == "i64" || clean == "u64" || clean == "isize" || clean == "usize" || clean == "f64" {
        return 4
    }
    0
}

func is_builtin_primitive(string ty) bool {
    var clean = parse_type(ty)
    return clean == "()"
        || clean == "never"
        || clean == "bool"
        || clean == "char"
        || clean == "str"
        || clean == "string"
        || clean == "i8"
        || clean == "i16"
        || clean == "int32"
        || clean == "i64"
        || clean == "isize"
        || clean == "u8"
        || clean == "u16"
        || clean == "u32"
        || clean == "u64"
        || clean == "usize"
        || clean == "f32"
        || clean == "f64"
}

func is_copy_type(string ty) bool {
    var clean = parse_type(ty)
    if clean == "()"
        || clean == "never"
        || clean == "bool"
        || clean == "char"
        || clean == "i8"
        || clean == "i16"
        || clean == "int32"
        || clean == "i64"
        || clean == "isize"
        || clean == "u8"
        || clean == "u16"
        || clean == "u32"
        || clean == "u64"
        || clean == "usize"
        || clean == "f32"
        || clean == "f64" {
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
    var end = text.len()
    while start < end && is_space(char_at(text, start)) {
        start = start + 1
    }
    while end > start && is_space(char_at(text, end - 1)) {
        end = end - 1
    }
    return slice(text, start, end)
}

func starts_with(string text, string prefix) bool {
    var prefix_len = prefix.len()
    if prefix_len > text.len() {
        return false
    }
    return slice(text, 0, prefix_len) == prefix
}

func ends_with(string text, string suffix) bool {
    var suffix_len = suffix.len()
    var text_len = text.len()
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
    while i < text.len() {
        if slice(text, i, i + 1) == needle {
            return i
        }
        i = i + 1
    }
    return 0 - 1
}

func find_last_char(string text, string needle) int32 {
    var i = text.len()
    while i > 0 {
        i = i - 1
        if slice(text, i, i + 1) == needle {
            return i
        }
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
    while i < text.len() {
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
