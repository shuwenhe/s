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
    bool is_array
    string array_len
    vec[string] args
}

func parse_type(string text) string {
    clean := normalize_type_text(trim_text(text))
    if clean == "" {
        return "unknown"
    }
    if is_builtin_primitive(clean) {
        return clean
    }
    if starts_with(clean, "&") {
        return "&" + parse_type(slice(clean, 5, clean.len()))
    }
    if starts_with(clean, "&") {
        return "&" + parse_type(slice(clean, 1, clean.len()))
    }
    if starts_with(clean, "[]") {
        return "[]" + parse_type(slice(clean, 2, clean.len()))
    }
    if starts_with(clean, "[") {
        close := find_char(clean, "]")
        if close > 0 {
            return slice(clean, 0, close + 1) + parse_type(slice(clean, close + 1, clean.len()))
        }
    }
    return clean
}

func parse_type_ref(string text) type_ref {
    canonical := parse_type(text)
    rest := canonical
    is_ref := false
    is_mut_ref := false
    is_slice := false
    is_array := false
    string array_len = ""
    if starts_with(rest, "&") {
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
    } else if starts_with(rest, "[") {
        close := find_char(rest, "]")
        if close > 0 {
            is_array = true
            array_len = trim_text(slice(rest, 1, close))
            rest = parse_type(slice(rest, close + 1, rest.len()))
        }
    }
    type_ref {
        canonical: canonical,
        base: base_type_name(rest),
        is_ref: is_ref,
        is_mut_ref: is_mut_ref,
        is_slice: is_slice,
        is_array: is_array,
        array_len: array_len,
        args: extract_type_args(rest),
    }
}

func dump_type_ref(type_ref ty) string {
    ty.canonical
}

func same_type_ref(type_ref left, type_ref right) bool {
    left.canonical == right.canonical
}

func type_arg(type_ref ty, int index) string {
    if index < 0 || index >= ty.args.len() {
        return "unknown"
    }
    parse_type(ty.args[index])
}

func generic_arity(string ty) int {
    args := extract_type_args(ty)
    args.len()
}

func has_unknown_component(string ty) bool {
    clean := parse_type(ty)
    if clean == "unknown" {
        return true
    }
    args := extract_type_args(clean)
    i := 0
    for i < args.len() {
        if parse_type(args[i]) == "unknown" {
            return true
        }
        i = i + 1
    }
    false
}

func rules_consistent() bool {
    if parse_type("  int  ") != "int" {
        return false
    }
    if !same_type("[]int", "[]int") {
        return false
    }
    if !same_type("[4]int", "[4]int") {
        return false
    }
    if same_type("[4]int", "[8]int") {
        return false
    }
    result_ref := parse_type_ref("(int, string)")
    if result_ref.base != "result" {
        return false
    }
    if type_arg(result_ref, 0) != "int" {
        return false
    }
    if type_arg(result_ref, 1) != "string" {
        return false
    }
    if generic_arity("(int, string)") != 2 {
        return false
    }
    ref_ref := parse_type_ref("&[]int")
    if !ref_ref.is_ref || !ref_ref.is_mut_ref {
        return false
    }
    array_ref := parse_type_ref("[4]int")
    if !array_ref.is_array || array_ref.array_len != "4" {
        return false
    }
    true
}

func dump_type(string ty) string {
    return parse_type(ty)
}

func base_type_name(string ty) string {
    clean := parse_type(ty)
    if starts_with(clean, "&") {
        return base_type_name(slice(clean, 5, clean.len()))
    }
    if starts_with(clean, "&") {
        return base_type_name(slice(clean, 1, clean.len()))
    }
    if starts_with(clean, "[]") {
        return base_type_name(slice(clean, 2, clean.len()))
    }
    if starts_with(clean, "[") {
        close := find_char(clean, "]")
        if close > 0 {
            return base_type_name(slice(clean, close + 1, clean.len()))
        }
    }
    bracket := find_char(clean, "[")
    if bracket >= 0 {
        return trim_text(slice(clean, 0, bracket))
    }
    angle := find_char(clean, "<")
    if angle >= 0 {
        return trim_text(slice(clean, 0, angle))
    }
    paren := find_char(clean, "(")
    if paren >= 0 {
        return trim_text(slice(clean, 0, paren))
    }
    return clean
}

func extract_type_args(string type_name) vec[string] {
    out := vec[string]()
    clean := parse_type(type_name)
    if starts_with(clean, "[") && !starts_with(clean, "[]") {
        close := find_char(clean, "]")
        if close > 0 {
            return extract_type_args(slice(clean, close + 1, clean.len()))
        }
    }
    open := find_char(clean, "[")
    close := find_last_char(clean, "]")
    if open < 0 || close <= open + 1 {
        return out
    }
    inner := slice(clean, open + 1, close)
    depth := 0
    start := 0
    i := 0
    for i < inner.len() {
        ch := char_at(inner, i)
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
    l := parse_type(left)
    r := parse_type(right)
    if l == r {
        return true
    }
    if l == "unknown" || r == "unknown" {
        return false
    }
    if is_tuple_type(l) || is_tuple_type(r) {
        return compatible_tuple_type(l, r)
    }
    lt := parse_type_ref(l)
    rt := parse_type_ref(r)
    if lt.is_ref != rt.is_ref || lt.is_mut_ref != rt.is_mut_ref || lt.is_slice != rt.is_slice {
        return false
    }
    if lt.is_array != rt.is_array {
        return false
    }
    if lt.is_array && lt.array_len != rt.array_len {
        return false
    }
    if lt.base != rt.base {
        return false
    }
    if lt.args.len() != rt.args.len() {
        return false
    }
    i := 0
    for i < lt.args.len() {
        if !compatible_type(lt.args[i], rt.args[i]) {
            return false
        }
        i = i + 1
    }
    true
}

func comparable_type(string ty) bool {
    clean := parse_type(ty)
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
    if starts_with(clean, "[") {
        return false
    }
    if is_tuple_type(clean) {
        items := extract_tuple_args(clean)
        i := 0
        for i < items.len() {
            if !comparable_type(items[i]) {
                return false
            }
            i = i + 1
        }
        return true
    }
    base := base_type_name(clean)
    if base == "option" || base == "result" {
        args := extract_type_args(clean)
        i := 0
        for i < args.len() {
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
    t := parse_type(target)
    s := parse_type(source)
    if t == s {
        return true
    }
    if s == "nil" {
        return is_nilable_type(t)
    }
    if t == "nil" {
        return s == "nil"
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

func is_nilable_type(string ty) bool {
    clean := parse_type(ty)
    if clean == "map" || clean == "fn" {
        return true
    }
    if starts_with(clean, "[]") || starts_with(clean, "&") {
        return true
    }
    base := base_type_name(clean)
    return base == "interface" || base == "trait"
}

func compatible_tuple_type(string left, string right) bool {
    l := parse_type(left)
    r := parse_type(right)
    if !is_tuple_type(l) || !is_tuple_type(r) {
        return false
    }
    la := extract_tuple_args(l)
    ra := extract_tuple_args(r)
    if la.len() != ra.len() {
        return false
    }
    i := 0
    for i < la.len() {
        if !compatible_type(la[i], ra[i]) {
            return false
        }
        i = i + 1
    }
    true
}

func assignable_tuple_type(string target, string source) bool {
    t := parse_type(target)
    s := parse_type(source)
    if !is_tuple_type(t) || !is_tuple_type(s) {
        return false
    }
    ta := extract_tuple_args(t)
    sa := extract_tuple_args(s)
    if ta.len() != sa.len() {
        return false
    }
    i := 0
    for i < ta.len() {
        if !assignable_type(ta[i], sa[i]) {
            return false
        }
        i = i + 1
    }
    true
}

func is_tuple_type(string ty) bool {
    clean := parse_type(ty)
    if clean.len() < 2 {
        return false
    }
    return starts_with(clean, "(") && ends_with(clean, ")")
}

func extract_tuple_args(string type_name) vec[string] {
    out := vec[string]()
    clean := parse_type(type_name)
    if !is_tuple_type(clean) {
        return out
    }
    inner := slice(clean, 1, clean.len() - 1)
    depth := 0
    start := 0
    i := 0
    for i < inner.len() {
        ch := char_at(inner, i)
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
    clean := parse_type(ty)
    return clean == "i8"
        || clean == "i16"
        || clean == "int"
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

func numeric_rank(string ty) int {
    clean := parse_type(ty)
    if clean == "i8" || clean == "u8" {
        return 1
    }
    if clean == "i16" || clean == "u16" {
        return 2
    }
    if clean == "int" || clean == "u32" || clean == "f32" {
        return 3
    }
    if clean == "i64" || clean == "u64" || clean == "isize" || clean == "usize" || clean == "f64" {
        return 4
    }
    0
}

func is_builtin_primitive(string ty) bool {
    clean := parse_type(ty)
    return clean == "()"
        || clean == "never"
        || clean == "bool"
        || clean == "char"
        || clean == "str"
        || clean == "string"
        || clean == "i8"
        || clean == "i16"
        || clean == "int"
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
    clean := parse_type(ty)
    if clean == "()"
        || clean == "never"
        || clean == "bool"
        || clean == "char"
        || clean == "i8"
        || clean == "i16"
        || clean == "int"
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
    clean := trim_text(ty)
    return find_char(clean, "[") >= 0 || find_char(clean, "<") >= 0
}

func normalize_type_text(string text) string {
    return trim_text(text)
}

func trim_text(string text) string {
    start := 0
    end := text.len()
    for start < end && is_space(char_at(text, start)) {
        start = start + 1
    }
    for end > start && is_space(char_at(text, end - 1)) {
        end = end - 1
    }
    return slice(text, start, end)
}

func starts_with(string text, string prefix) bool {
    prefix_len := prefix.len()
    if prefix_len > text.len() {
        return false
    }
    return slice(text, 0, prefix_len) == prefix
}

func ends_with(string text, string suffix) bool {
    suffix_len := suffix.len()
    text_len := text.len()
    if suffix_len > text_len {
        return false
    }
    return slice(text, text_len - suffix_len, text_len) == suffix
}

func is_space(string ch) bool {
    return ch == " " || ch == "\n" || ch == "\t" || ch == "\r"
}

func find_char(string text, string needle) int {
    i := 0
    for i < text.len() {
        if slice(text, i, i + 1) == needle {
            return i
        }
        i = i + 1
    }
    return 0 - 1
}

func find_last_char(string text, string needle) int {
    i := text.len()
    for i > 0 {
        i = i - 1
        if slice(text, i, i + 1) == needle {
            return i
        }
    }
    return 0 - 1
}

func extract_section(string text, string open, string close) string {
    start := find_char(text, open)
    if start < 0 {
        return ""
    }
    depth := 0
    i := start
    for i < text.len() {
        ch := slice(text, i, i + 1)
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
