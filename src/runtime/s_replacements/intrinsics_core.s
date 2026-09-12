func string_len( text string): int {
    return text.len(
}

func int_to_string( value int): string {
    return value.to_string(
}

func string_concat( left string, string right): string {
    return left + right
}

func string_replace( text string, string old, string new): string {
    return text.replace(old, new
}

func string_char_at( text string, int index): string {
    if index < 0 || index >= len(text) {
        return ""
    }
    return text.slice(index, index+1
}

func string_slice( text string, int start, int end): string {
    return text.slice(start, end
}