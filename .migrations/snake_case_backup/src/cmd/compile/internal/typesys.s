package compile.internal.typesys

use std.prelude.charAt
use std.prelude.len
use std.prelude.slice
use std.vec.Vec

func ParseType(string text) string {
    var clean = normalizeTypeText(trimText(text))
    if clean == "" {
        return "unknown"
    }
    if clean == "()" || clean == "never" || clean == "bool" || clean == "int32" || clean == "usize" || clean == "u8" || clean == "string" {
        return clean
    }
    if startsWith(clean, "&mut ") {
        return "&mut " + ParseType(slice(clean, 5, len(clean)))
    }
    if startsWith(clean, "&") {
        return "&" + ParseType(slice(clean, 1, len(clean)))
    }
    if startsWith(clean, "[]") {
        return "[]" + ParseType(slice(clean, 2, len(clean)))
    }
    return clean
}

func DumpType(string ty) string {
    return ParseType(ty)
}

func BaseTypeName(string ty) string {
    var clean = ParseType(ty)
    if startsWith(clean, "&mut ") {
        return BaseTypeName(slice(clean, 5, len(clean)))
    }
    if startsWith(clean, "&") {
        return BaseTypeName(slice(clean, 1, len(clean)))
    }
    if startsWith(clean, "[]") {
        return BaseTypeName(slice(clean, 2, len(clean)))
    }
    var bracket = findChar(clean, "[")
    if bracket >= 0 {
        return trimText(slice(clean, 0, bracket))
    }
    var angle = findChar(clean, "<")
    if angle >= 0 {
        return trimText(slice(clean, 0, angle))
    }
    var paren = findChar(clean, "(")
    if paren >= 0 {
        return trimText(slice(clean, 0, paren))
    }
    return clean
}

func SameType(string left, string right) bool {
    return ParseType(left) == ParseType(right)
}

func IsBuiltinPrimitive(string ty) bool {
    var clean = ParseType(ty)
    return clean == "()" || clean == "never" || clean == "bool" || clean == "int32" || clean == "usize" || clean == "u8" || clean == "string"
}

func IsCopyType(string ty) bool {
    var clean = ParseType(ty)
    if clean == "()" || clean == "never" || clean == "bool" || clean == "int32" || clean == "usize" || clean == "u8" {
        return true
    }
    if startsWith(clean, "&") {
        return true
    }
    return false
}

func IsReferenceType(string ty) bool {
    return startsWith(trimText(ty), "&")
}

func IsSliceType(string ty) bool {
    return startsWith(trimText(ty), "[]")
}

func IsGenericType(string ty) bool {
    var clean = trimText(ty)
    return findChar(clean, "[") >= 0 || findChar(clean, "<") >= 0
}

func normalizeTypeText(string text) string {
    return trimText(text)
}

func trimText(string text) string {
    var start = 0
    var end = len(text)
    while start < end && isSpace(charAt(text, start)) {
        start = start + 1
    }
    while end > start && isSpace(charAt(text, end - 1)) {
        end = end - 1
    }
    return slice(text, start, end)
}

func startsWith(string text, string prefix) bool {
    var prefixLen = len(prefix)
    if prefixLen > len(text) {
        return false
    }
    return slice(text, 0, prefixLen) == prefix
}

func endsWith(string text, string suffix) bool {
    var suffixLen = len(suffix)
    var textLen = len(text)
    if suffixLen > textLen {
        return false
    }
    return slice(text, textLen - suffixLen, textLen) == suffix
}

func isSpace(string ch) bool {
    return ch == " " || ch == "\n" || ch == "\t" || ch == "\r"
}

func findChar(string text, string needle) int32 {
    var i = 0
    while i < len(text) {
        if slice(text, i, i + 1) == needle {
            return i
        }
        i = i + 1
    }
    return 0 - 1
}

func extractSection(string text, string open, string close) string {
    var start = findChar(text, open)
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
