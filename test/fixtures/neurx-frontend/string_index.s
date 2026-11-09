package string_index_probe
extern "intrinsic" func __std_byte_string(int value) string
func main() int {
    string value = "A"
    string ch = __std_byte_string(value[0])
    if ch == "A" && value[0] == 65 { return 0 }
    return 1
}
