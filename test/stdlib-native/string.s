package main
import ("std.string"; "std.time")
extern "intrinsic" func __std_string_array_concat(string[] left, string[] right) string[]
func binary_text(int input) string {
    encoded := input
    text := ""
    while encoded > 1 {
        if encoded % 2 == 0 { text = text + "a" } else { text = text + "b" }
        encoded = encoded / 2
    }
    return text
}
func naive_index(string text, string needle) int {
    if len(needle) == 0 { return 0 }
    position := 0
    while position <= len(text) - len(needle) {
        index := 0
        same := true
        while index < len(needle) {
            left, left_error := std.string.byte_at(text, position + index)
            right, right_error := std.string.byte_at(needle, index)
            if left != right { same = false; break }
            index = index + 1
        }
        if same { return position }
        position = position + 1
    }
    return -1
}
func exhaustive_search() int {
    subject := 1
    while subject < 128 {
        pattern := 1
        text := binary_text(subject)
        while pattern < 32 {
            needle := binary_text(pattern)
            if std.string.index_of(text, needle) != naive_index(text, needle) { return 24 }
            pattern = pattern + 1
        }
        subject = subject + 1
    }
    return 0
}
func main() int {
    if std.string.compare("abc", "abd") != -1 || std.string.compare("abc", "abc") != 0 || std.string.compare("abcd", "abc") != 1 { return 1 }
    if std.string.index_of("aaaaab", "aaab") != 2 || std.string.index_of("abc", "") != 0 || std.string.index_of("abc", "d") != -1 { return 2 }
    value, error := std.string.slice("abc", -1, 2)
    if error.code != 22 { return 3 }
    second_value, second_error := std.string.slice("abc", 1, 3)
    if second_error.code != 0 || second_value != "bc" { return 4 }
    byte, byte_error := std.string.byte_at("abc", 3)
    if byte_error.code != 22 { return 5 }
    fields, split_error := std.string.split("--a----b--", "--")
    if split_error.code != 0 || len(fields) != 5 || fields[0] != "" || fields[1] != "a" || fields[2] != "" || fields[3] != "b" || fields[4] != "" { return 6 }
    if std.string.join(fields, "--") != "--a----b--" { return 7 }
    replaced, replace_error := std.string.replace("aaaaa", "aa", "b")
    if replace_error.code != 0 || replaced != "bba" { return 8 }
    ignored, empty_error := std.string.split("x", "")
    if empty_error.code != 22 { return 9 }
    if std.string.trim_ascii(" \t\r\nhello \n") != "hello" || std.string.lower_ascii("A-Z!") != "a-z!" || std.string.upper_ascii("a-z!") != "A-Z!" { return 10 }
    if !std.string.starts_with("abc", "ab") || !std.string.ends_with("abc", "bc") || std.string.contains("abc", "bd") { return 11 }
    minimum, minimum_error := std.string.parse_int("-9223372036854775808")
    maximum, maximum_error := std.string.parse_int("9223372036854775807")
    if minimum_error.code != 0 || maximum_error.code != 0 || std.string.format_int(minimum) != "-9223372036854775808" || std.string.format_int(maximum) != "9223372036854775807" { return 12 }
    bad, bad_error := std.string.parse_int("9223372036854775808")
    if bad_error.code != 34 { return 13 }
    bad2, bad_error2 := std.string.parse_int("-9223372036854775809")
    if bad_error2.code != 34 { return 14 }
    bad3, bad_error3 := std.string.parse_int("+")
    if bad_error3.code != 22 { return 15 }
    bad4, bad_error4 := std.string.parse_int(" 1")
    if bad_error4.code != 22 { return 16 }
    nul, nul_error := std.string.from_byte(0)
    if nul_error.code != 0 { return 22 }
    invalid_byte, invalid_error := std.string.from_byte(256)
    if invalid_error.code != 22 { return 23 }
    if len(nul) != 1 || std.string.index_of("a" + nul + "b", nul) != 1 { return 17 }
    nul_byte, nul_byte_error := std.string.byte_at(nul, 0)
    if nul_byte_error.code != 0 || nul_byte != 0 { return 18 }
    repeated := "a"
    index := 0
    while index < 16 { repeated = repeated + repeated; index = index + 1 }
    needle := "a"
    index = 0
    while index < 15 { needle = needle + needle; index = index + 1 }
    clock, clock_error := std.time.timer_start()
    if clock_error.code != 0 { return 19 }
    if std.string.index_of(repeated + "b", needle + "b") != 32768 { return 20 }
    elapsed, elapsed_error := std.time.elapsed_time(clock)
    if elapsed_error.code != 0 { return 21 }
    println("search_ns=" + std.string.format_int(elapsed.nanoseconds))
    dense := "x,"
    index = 0
    while index < 14 { dense = dense + dense; index = index + 1 }
    reset_error := std.time.timer_reset(clock*)
    if reset_error.code != 0 { return 25 }
    dense_fields, dense_error := std.string.split(dense, ",")
    if dense_error.code != 0 || len(dense_fields) != 16385 || dense_fields[16384] != "" || std.string.join(dense_fields, ",") != dense { return 26 }
    split_elapsed, split_time_error := std.time.elapsed_time(clock)
    if split_time_error.code != 0 { return 27 }
    println("split_ns=" + std.string.format_int(split_elapsed.nanoseconds))
    original := string[]{"left"}
    concatenated := __std_string_array_concat(original, string[]{"right"})
    concatenated[0] = "changed"
    if original[0] != "left" || concatenated[0] != "changed" || concatenated[1] != "right" { return 28 }
    empty_joined := __std_string_array_concat(string[](), string[]())
    if len(empty_joined) != 0 { return 29 }
    if exhaustive_search() != 0 { return 24 }
    println("string: PASS")
    return 0
}
