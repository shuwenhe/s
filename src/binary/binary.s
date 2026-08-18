package std.binary

use std.encoding.normalize_byte

func u64_le_bytes([]int bytes, int offset) int {
    if offset < 0 || offset + 8 > len(bytes) {
        return 0
    }
    int value = 0
    int multiplier = 1
    int i = 0
    while i < 8 {
        value = value + normalize_byte(bytes[offset + i]) * multiplier
        multiplier = multiplier * 256
        i = i + 1
    }
    return value
}

func u64_le_string(string data, int offset) int {
    if offset < 0 || offset + 8 > len(data) {
        return 0
    }
    int value = 0
    int multiplier = 1
    int i = 0
    while i < 8 {
        value = value + normalize_byte(int(byte(data[offset + i]))) * multiplier
        multiplier = multiplier * 256
        i = i + 1
    }
    return value
}

func i32_le_string(string data, int offset) int {
    if offset < 0 || offset + 4 > len(data) {
        return 0
    }
    int value = 0
    int multiplier = 1
    int i = 0
    while i < 4 {
        value = value + normalize_byte(int(byte(data[offset + i]))) * multiplier
        multiplier = multiplier * 256
        i = i + 1
    }
    return value
}

func parse_int_at_bytes([]int bytes, int pos) int {
    if pos < 0 || pos >= len(bytes) {
        return 0
    }
    int value = 0
    int cursor = pos
    while cursor < len(bytes) {
        int c = bytes[cursor]
        if c < 48 || c > 57 {
            break
        }
        value = value * 10 + (c - 48)
        cursor = cursor + 1
    }
    return value
}
