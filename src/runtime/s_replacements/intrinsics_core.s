
func string_len(text: string): int {
    return text.len()
}

func int_to_string(value: int): string {
    return value.to_string()
}

func string_concat(left: string, right: string): string {
    return left + right
}

func string_replace(text: string, old: string, new: string): string {
    return text.replace(old, new)
}

func string_char_at(text: string, index: int): string {
    if index < 0 || index >= text.len() {
        return ""
    }
    return text.slice(index, index+1)
}

func string_slice(text: string, start: int, end: int): string {
    return text.slice(start, end)
}
