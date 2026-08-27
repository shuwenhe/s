package compile.internal.noder
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.slices

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
    start := 0
    end := len(text)
    for start < end {
        ch := char_at(text, start)
        if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            start = start + 1
        } else {
            break
        }
    }
    for end > start {
        ch := char_at(text, end - 1)
        if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            end = end - 1
        } else {
            break
        }
    }
    slice(text, start, end)
}

func split_lines(string text) string[] {
    out := string[]()
    start := 0
    i := 0
    for i < len(text) {
        if char_at(text, i) == "\n" {
            out = append(out, slice(text, start, i))
            start = i + 1
        }
        i = i + 1
    }
    out = append(out, slice(text, start, len(text)))
    out
}

func split_words(string line) string[] {
    out := string[]()
    current := ""
    i := 0
    for i < len(line) {
        ch := char_at(line, i)
        if ch == " " || ch == "\t" {
            if current != "" {
                out = append(out, current)
                current = ""
            }
        } else {
            current = current + ch
        }
        i = i + 1
    }
    if current != "" {
        out = append(out, current)
    }
    out
}

func normalize_import_path(string raw) string {
    text := trim_spaces(raw)
    if starts_with(text, "\"") && ends_with(text, "\"") && len(text) >= 2 {
        return slice(text, 1, len(text) - 1
    }
    text
}

func join_path(string[] parts) string {
    if len(parts) == 0 {
        return ""
    }
    out := parts[0]
    i := 1
    for i < len(parts) {
        out = out + "/" + parts[i]
        i = i + 1
    }
    out
}

func ident_or_default(string name, string fallback) string {
    t := trim_spaces(name)
    if t == "" {
        return fallback
    }
    t
}

func fmt_pos(string path, int line, int column) string {
    path + ":" + to_string(line) + ":" + to_string(column)
}
