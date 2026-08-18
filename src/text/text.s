package std.text

func int_to_string(int value) string {
    if value == 0 {
        return "0"
    }
    string result = ""
    int current = value
    if current < 0 {
        current = 0 - current
    }
    while current > 0 {
        int digit = current - (current / 10) * 10
        result = string(48 + digit) + result
        current = current / 10
    }
    if value < 0 {
        return "-" + result
    }
    return result
}

func int64_to_string(int64 value) string {
    if value == 0 {
        return "0"
    }
    string result = ""
    int64 current = value
    if current < 0 {
        current = 0 - current
    }
    while current > 0 {
        int64 digit = current % 10
        result = string(48 + int(digit)) + result
        current = current / 10
    }
    if value < 0 {
        return "-" + result
    }
    return result
}

func parse_int_default(string text, int fallback) int {
    if len(text) == 0 {
        return fallback
    }
    int sign = 1
    int index = 0
    if string(text[0]) == "-" {
        sign = -1
        index = 1
    }
    int value = 0
    while index < len(text) {
        int digit = int(text[index]) - 48
        if digit < 0 || digit > 9 {
            return fallback
        }
        value = value * 10 + digit
        index = index + 1
    }
    sign * value
}

func normalize_byte(int value) int {
    int current = value
    if current < 0 {
        current = current + 256
    }
    current
}

func is_ascii_space(int value) bool {
    int current = normalize_byte(value)
    current == 32 || current == 9 || current == 10 || current == 13
}

func ascii_to_lower(int value) int {
    int current = normalize_byte(value)
    if current >= 65 && current <= 90 {
        return current + 32
    }
    return current
}

func is_ascii_printable(int value) bool {
    int current = normalize_byte(value)
    current >= 32 && current <= 126
}

func normalize_ascii_text(string text) string {
    string result = ""
    int i = 0
    while i < len(text) {
        int val = ascii_to_lower(int(byte(text[i])))
        if is_ascii_printable(val) {
            result = result + string(byte(val))
        }
        i = i + 1
    }
    return result
}

func bytes_to_string([]int bytes) string {
    string result = ""
    int i = 0
    while i < len(bytes) {
        result = result + string(normalize_byte(bytes[i]))
        i = i + 1
    }
    return result
}

func str_to_bytes(string text) []int {
    []int result
    int i = 0
    while i < len(text) {
        result = append(result, normalize_byte(int(byte(text[i]))))
        i = i + 1
    }
    return result
}

func bytes_to_string_range([]int bytes, int start, int length) string {
    string result = ""
    int i = 0
    while i < length && start + i < len(bytes) {
        result = result + string(normalize_byte(bytes[start + i]))
        i = i + 1
    }
    return result
}
