package compile.internal.noder
import (
    "std"
    "std.prelude"
)
func starts_with(string text, string prefix) bool {
    if std.prelude.len(text) < std.prelude.len(prefix) {
        return false
    }
    std.prelude.slice(text, 0, std.prelude.len(prefix)) == prefix
}
func ends_with(string text, string suffix) bool {
    if std.prelude.len(text) < std.prelude.len(suffix) {
        return false
    }
    std.prelude.slice(text, std.prelude.len(text) - std.prelude.len(suffix), std.prelude.len(text)) == suffix
}
func trim_spaces(string text) string {
    start := 0
    end := std.prelude.len(text)
    for start < end {
        ch := std.prelude.char_at(text, start)
        if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            start = start + 1
        } else {
            break
        }
    }
    for end > start {
        ch := std.prelude.char_at(text, end - 1)
        if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
            end = end - 1
        } else {
            break
        }
    }
    std.prelude.slice(text, start, end)
}
func split_lines(string text) string[] {
    out := string[]()
    start := 0
    i := 0
    for i < std.prelude.len(text) {
        if std.prelude.char_at(text, i) == "\n" {
            out = append(out, std.prelude.slice(text, start, i))
            start = i + 1
        }
        i = i + 1
    }
    out = append(out, std.prelude.slice(text, start, std.prelude.len(text)))
    out
}
func split_words(string line) string[] {
    out := string[]()
    current := ""
    i := 0
    for i < std.prelude.len(line) {
        ch := std.prelude.char_at(line, i)
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
    if starts_with(text, "\"") && ends_with(text, "\"") && std.prelude.len(text) >= 2 {
        return std.prelude.slice(text, 1, std.prelude.len(text) - 1
    }
    text
}
func join_path(string[] parts) string {
    if std.prelude.len(parts) == 0 {
        return ""
    }
    out := parts[0]
    i := 1
    for i < std.prelude.len(parts) {
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
    path + ":" + std.prelude.to_string(line) + ":" + std.prelude.to_string(column)
