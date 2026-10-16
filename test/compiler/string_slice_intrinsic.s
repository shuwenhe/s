package main

extern "intrinsic" func __string_slice(string text, int start, int end) string

func main() int {
    if __string_slice("abc", 0, 3) != "abc" { return 1 }
    if __string_slice("abc", 1, 2) != "b" { return 2 }
    if __string_slice("abc", 3, 3) != "" { return 3 }
    if __string_slice("", 0, 0) != "" { return 4 }
    if __string_slice("éx", 0, 2) != "é" { return 5 }
    if __string_slice("éx", 2, 3) != "x" { return 6 }
    return 0
}
