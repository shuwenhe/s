package std.text

func bytes_to_string([]int bytes) string {
    string result = ""
    int i = 0
    while i < len(bytes) {
        result = result + string(bytes[i])
        i = i + 1
    }
    return result
}

func bytes_to_string_range([]int bytes, int start, int length) string {
    string result = ""
    int i = 0
    while i < length && start + i < len(bytes) {
        result = result + string(bytes[start + i])
        i = i + 1
    }
    return result
}
