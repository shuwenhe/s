package main
extern "intrinsic" func __host_char_at(string text, int index) string;
func join(string left, string right) string {
    return left + right
}

func main() {
    string value = join("self", "-") + join("host", "ing")
    if len(value) == 12 && __host_char_at(value, 4) == "-" && value == "self-hosting" {
        return 42
    }
    return 1
}
