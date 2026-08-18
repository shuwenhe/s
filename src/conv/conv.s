package std.conv

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
