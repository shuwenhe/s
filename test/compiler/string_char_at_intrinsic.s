package main

extern "intrinsic" func __string_char_at(string text, int index) string

func main() int {
    if __string_char_at("abc", 0) != "a" { return 1 }
    if __string_char_at("abc", 1) != "b" { return 2 }
    if __string_char_at("abc", 2) != "c" { return 3 }
    if __string_char_at("", 0) != "" { return 4 }
    if __string_char_at("abc", -1) != "" { return 5 }
    if __string_char_at("abc", 3) != "" { return 6 }
    // Existing runtime indexing selects bytes, not Unicode code points.
    if __string_char_at("éx", 2) != "x" { return 7 }
    if __string_char_at("éx", 3) != "" { return 8 }
    return 0
}
