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
    for current > 0 {
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
    for current > 0 {
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
    for index < len(text) {
        int digit = int(text[index]) - 48
        if digit < 0 || digit > 9 {
            return fallback
        }
        value = value * 10 + digit
        index = index + 1
    }
    sign * value
}

func parse_int(string text) int {
    parse_int_default(text, 0)
}

func string_to_int(string text) int {
    int result = 0
    int index = 0
    int start = 0
    bool negative = false
    if len(text) > 0 && string(text[0]) == "-" {
        negative = true
        start = 1
    }
    index = start
    for index < len(text) {
        int digit = int(text[index]) - 48
        if digit >= 0 && digit <= 9 {
            result = result * 10 + digit
        }
        index = index + 1
    }
    if negative {
        result = -result
    }
    return result
}

func extract_int_default(string text, int fallback) int {
    if len(text) == 0 {
        return fallback
    }
    int index = 0
    int sign = 1
    if string(text[0]) == "-" {
        sign = -1
        index = 1
    } else if string(text[0]) == "+" {
        index = 1
    }
    int value = 0
    bool seen = false
    for index < len(text) {
        int digit = int(text[index]) - 48
        if digit >= 0 && digit <= 9 {
            value = value * 10 + digit
            seen = true
        }
        index = index + 1
    }
    if !seen {
        return fallback
    }
    return sign * value
}

func float_to_string_precision(float value, int precision) string {
    if precision < 0 {
        precision = 0
    }
    bool negative = false
    float current = value
    if current < 0.0 {
        negative = true
        current = 0.0 - current
    }

    int int_part = int(current)
    float frac = current - float(int_part)
    string result = int_to_string(int_part)

    if precision == 0 {
        if negative {
            return "-" + result
        }
        return result
    }

    result = result + "."
    int i = 0
    for i < precision {
        frac = frac * 10.0
        int digit = int(frac)
        if digit < 0 {
            digit = 0
        }
        if digit > 9 {
            digit = 9
        }
        result = result + string(48 + digit)
        frac = frac - float(digit)
        i = i + 1
    }

    if negative {
        return "-" + result
    }
    return result
}

func float_to_string(float value) string {
    return float_to_string_precision(value, 3
}
