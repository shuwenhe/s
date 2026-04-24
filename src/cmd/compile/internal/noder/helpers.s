package compile.internal.noder

use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.vec.vec

func starts_with(string text, string prefix) bool {
    if len(text) < len(prefix) {
        return false
    }
    slice(text, 0, len(prefix)) == prefix
}

func ends_with(string text, string suffix) bool {
    if len(text) < len(suffix) {
        return false
    }
    slice(text, len(text) - len(suffix), len(text)) == suffix
}

func trim_spaces(string text) string {
    var start = 0
    var end = len(text)
    while start < end {
        var ch = char_at(text, start)
        if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            start = start + 1
        } else {
            break
        }
    }
    while end > start {
        var ch = char_at(text, end - 1)
        if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            end = end - 1
        } else {
            break
        }
    }
    slice(text, start, end)
}

func split_lines(string text) vec[string] {
    var out = vec[string]()
    var start = 0
    var i = 0
    while i < len(text) {
        if char_at(text, i) == "\n" {
            out.push(slice(text, start, i))
            start = i + 1
        }
        i = i + 1
    }
    out.push(slice(text, start, len(text)))
    out
}

func split_words(string line) vec[string] {
    var out = vec[string]()
    var current = ""
    var i = 0
    while i < len(line) {
        var ch = char_at(line, i)
        if ch == " " || ch == "\t" {
            if current != "" {
                out.push(current)
                current = ""
            }
        } else {
            current = current + ch
        }
        i = i + 1
    }
    if current != "" {
        out.push(current)
    }
    out
}

func normalize_import_path(string raw) string {
    var text = trim_spaces(raw)
    if starts_with(text, "\"") && ends_with(text, "\"") && len(text) >= 2 {
        return slice(text, 1, len(text) - 1)
    }
    text
}

func join_path(vec[string] parts) string {
    if parts.len() == 0 {
        return ""
    }
    var out = parts[0]
    var i = 1
    while i < parts.len() {
        out = out + "/" + parts[i]
        i = i + 1
    }
    out
}

func ident_or_default(string name, string fallback) string {
    var t = trim_spaces(name)
    if t == "" {
        return fallback
    }
    t
}

func fmt_pos(string path, int line, int column) string {
    path + ":" + to_string(line) + ":" + to_string(column)
}
