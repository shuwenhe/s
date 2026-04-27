// S 实现：intrinsics_core.py
// 提供字符串基础操作

fn string_len(text: string): int {
    return text.len()
}

fn int_to_string(value: int): string {
    return value.to_string()
}

fn string_concat(left: string, right: string): string {
    return left + right
}

fn string_replace(text: string, old: string, new: string): string {
    return text.replace(old, new)
}

fn string_char_at(text: string, index: int): string {
    if index < 0 || index >= text.len() {
        return ""
    }
    return text.slice(index, index+1)
}

fn string_slice(text: string, start: int, end: int): string {
    return text.slice(start, end)
}
