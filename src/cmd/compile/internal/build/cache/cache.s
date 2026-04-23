package compile.internal.build.cache

use std.fs.read_to_string
use std.fs.write_text_file
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string

func cache_hit(string source_path, string source_text, string phase) bool {
    var stamp_path = source_path + "." + phase + ".cache"
    var cached = read_to_string(stamp_path)
    if cached.is_err() {
        return false
    }
    cached.unwrap() == dependency_fingerprint(source_path, source_text, phase)
}

func update_cache(string source_path, string source_text, string phase) bool {
    var stamp_path = source_path + "." + phase + ".cache"
    var write = write_text_file(stamp_path, dependency_fingerprint(source_path, source_text, phase))
    if write.is_err() {
        return false
    }

    var pkg = package_name(source_text)
    var export_stamp = export_stamp_path(pkg)
    var export_write = write_text_file(export_stamp, export_signature(source_text))
    !export_write.is_err()
}

func dependency_fingerprint(string source_path, string source_text, string phase) string {
    var own = fingerprint(source_text)
    var pkg = package_name(source_text)
    var imports = import_signature(source_text)
    var exports = export_signature(source_text)
    var propagated = import_export_propagation_signature(source_text)
    phase + ":" + source_path + ":" + pkg + ":" + own + ":" + imports + ":" + exports + ":" + propagated
}

func fingerprint(string source_text) string {
    var funcs = count_token(source_text, "func ")
    var structs = count_token(source_text, "struct ")
    var calls = count_token(source_text, " call")
    var uses = count_token(source_text, "\nuse ")
    var pkg = package_name(source_text)
    pkg + ":" + to_string(len(source_text)) + ":" + to_string(funcs) + ":" + to_string(structs) + ":" + to_string(calls) + ":" + to_string(uses)
}

func import_signature(string source_text) string {
    var sig = "imports"
    var cursor = 0
    while cursor < len(source_text) {
        var line_end = index_of_from(source_text, "\n", cursor)
        if line_end < 0 {
            line_end = len(source_text)
        }
        var line = trim_spaces(slice(source_text, cursor, line_end))
        if starts_with(line, "use ") {
            var path = use_path_from_line(line)
            sig = sig + "|" + path
        }
        cursor = line_end + 1
    }
    sig
}

func export_signature(string source_text) string {
    var pub_funcs = count_token(source_text, "\npub func ") + count_token(source_text, "\npub\nfunc ")
    var pub_structs = count_token(source_text, "\npub struct ")
    var pub_enums = count_token(source_text, "\npub enum ")
    var pub_traits = count_token(source_text, "\npub trait ")
    var pub_impls = count_token(source_text, "\npub impl ")
    "exports:" + to_string(pub_funcs) + ":" + to_string(pub_structs) + ":" + to_string(pub_enums) + ":" + to_string(pub_traits) + ":" + to_string(pub_impls)
}

func import_export_propagation_signature(string source_text) string {
    var sig = "deps"
    var cursor = 0
    while cursor < len(source_text) {
        var line_end = index_of_from(source_text, "\n", cursor)
        if line_end < 0 {
            line_end = len(source_text)
        }
        var line = trim_spaces(slice(source_text, cursor, line_end))
        if starts_with(line, "use ") {
            var path = use_path_from_line(line)
            var dep_export = read_to_string(export_stamp_path(path))
            if dep_export.is_err() {
                sig = sig + "|" + path + "=missing"
            } else {
                sig = sig + "|" + path + "=" + dep_export.unwrap()
            }
        }
        cursor = line_end + 1
    }
    sig
}

func export_stamp_path(string pkg_or_use_path) string {
    ".s.cache.export." + sanitize_key(pkg_or_use_path)
}

func sanitize_key(string text) string {
    var out = ""
    var i = 0
    while i < len(text) {
        var ch = slice(text, i, i + 1)
        if ch == "." || ch == "/" || ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            out = out + "_"
        } else {
            out = out + ch
        }
        i = i + 1
    }
    out
}

func use_path_from_line(string line) string {
    var payload = trim_spaces(slice(line, 4, len(line)))
    var as_pos = index_of(payload, " as ")
    if as_pos < 0 {
        return payload
    }
    trim_spaces(slice(payload, 0, as_pos))
}

func trim_spaces(string text) string {
    var start = 0
    var end = len(text)
    while start < end {
        var ch0 = slice(text, start, start + 1)
        if ch0 != " " && ch0 != "\t" && ch0 != "\n" && ch0 != "\r" {
            break
        }
        start = start + 1
    }
    while end > start {
        var ch1 = slice(text, end - 1, end)
        if ch1 != " " && ch1 != "\t" && ch1 != "\n" && ch1 != "\r" {
            break
        }
        end = end - 1
    }
    slice(text, start, end)
}

func starts_with(string text, string prefix) bool {
    if len(prefix) > len(text) {
        return false
    }
    slice(text, 0, len(prefix)) == prefix
}

func package_name(string source_text) string {
    var marker = "package "
    var start = index_of(source_text, marker)
    if start < 0 {
        return "unknown"
    }
    start = start + len(marker)
    var end = start
    while end < len(source_text) {
        var ch = slice(source_text, end, end + 1)
        if ch == " " || ch == "\n" || ch == "\r" || ch == "\t" {
            break
        }
        end = end + 1
    }
    slice(source_text, start, end)
}

func index_of(string text, string token) int32 {
    if token == "" {
        return 0
    }
    var i = 0
    while i <= len(text) - len(token) {
        if slice(text, i, i + len(token)) == token {
            return i
        }
        i = i + 1
    }
    -1
}

func index_of_from(string text, string token, int32 start) int32 {
    if token == "" {
        return start
    }
    var i = start
    while i <= len(text) - len(token) {
        if slice(text, i, i + len(token)) == token {
            return i
        }
        i = i + 1
    }
    -1
}

func count_token(string text, string token) int32 {
    if token == "" {
        return 0
    }

    var total = 0
    var i = 0
    while i <= len(text) - len(token) {
        if slice(text, i, i + len(token)) == token {
            total = total + 1
            i = i + len(token)
        } else {
            i = i + 1
        }
    }
    total
}
