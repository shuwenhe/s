package compile.selfhost.lexer

extern "intrinsic" func host_args() []string;
extern "intrinsic" func __host_read_to_string(string path) string;
extern "intrinsic" func __host_write_text_file(string path, string contents) int;
extern "intrinsic" func __host_char_at(string text, int index) string;
extern "intrinsic" func __host_byte_at(string text, int index) int;
extern "intrinsic" func __host_slice(string text, int start, int end) string;

func is_digit(string ch) bool {
    return ch >= "0" && ch <= "9"
}

func is_alpha(string ch) bool {
    return (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch == "_"
}

func is_ident_continue(string ch) bool {
    return is_alpha(ch) || is_digit(ch)
}

func keyword_kind(string text) string {
    if text == "fn" || text == "func" { return "FN" }
    if text == "let" { return "LET" }
    if text == "var" { return "VAR" }
    if text == "package" { return "PACKAGE" }
    if text == "use" { return "USE" }
    if text == "as" { return "AS" }
    if text == "if" { return "IF" }
    if text == "else" { return "ELSE" }
    if text == "for" { return "FOR" }
    if text == "while" { return "WHILE" }
    if text == "return" { return "RETURN" }
    if text == "break" { return "BREAK" }
    if text == "continue" { return "CONTINUE" }
    if text == "true" { return "TRUE" }
    if text == "false" { return "FALSE" }
    return "IDENTIFIER"
}

func symbol_kind(string text) string {
    if text == "+" { return "+" }
    if text == "-" { return "-" }
    if text == "*" { return "*" }
    if text == "/" { return "/" }
    if text == "%" { return "%" }
    if text == "!" { return "!" }
    if text == "=" { return "=" }
    if text == "==" { return "==" }
    if text == "!=" { return "!=" }
    if text == "&&" { return "&&" }
    if text == "&" { return "&" }
    if text == "||" { return "||" }
    if text == "<" { return "<" }
    if text == "<=" { return "<=" }
    if text == ">" { return ">" }
    if text == ">=" { return ">=" }
    if text == "(" { return "(" }
    if text == ")" { return ")" }
    if text == "[" { return "[" }
    if text == "]" { return "]" }
    if text == "{" { return "{" }
    if text == "}" { return "}" }
    if text == "," { return "," }
    if text == "." { return "." }
    if text == ":" { return ":" }
    if text == ";" { return ";" }
    return "UNKNOWN"
}

func digit_text(int value) string {
    if value == 0 { return "0" }
    if value == 1 { return "1" }
    if value == 2 { return "2" }
    if value == 3 { return "3" }
    if value == 4 { return "4" }
    if value == 5 { return "5" }
    if value == 6 { return "6" }
    if value == 7 { return "7" }
    if value == 8 { return "8" }
    return "9"
}

func int_text(int value) string {
    if value < 10 { return digit_text(value) }
    return int_text(value / 10) + digit_text(value % 10)
}

func hex_digit(int value) string {
    if value < 10 { return digit_text(value) }
    if value == 10 { return "a" }
    if value == 11 { return "b" }
    if value == 12 { return "c" }
    if value == 13 { return "d" }
    if value == 14 { return "e" }
    return "f"
}

func hex_text(string text) string {
    var output = ""
    var index = 0
    while index < len(text) {
        let value = __host_byte_at(text, index)
        output = output + hex_digit(value / 16) + hex_digit(value % 16)
        index = index + 1
    }
    return output
}

func lexer_error(string code, int line, int column, string message) string {
    return "ERROR|" + code + "|" + int_text(line) + "|" + int_text(column) + "|" + message + "\n"
}

func append_token(string output, string kind, string lexeme, int line, int column) string {
    return output + kind + "|" + hex_text(lexeme) + "|" + int_text(line) + "|" + int_text(column) + "\n"
}

func dump_tokens(string source) string {
    var output = ""
    var i = 0
    var line = 1
    var column = 1
    let source_len = len(source)

    while i < source_len {
        let ch = __host_char_at(source, i)
        if ch == " " || ch == "\t" || ch == "\r" {
            i = i + 1
            column = column + 1
            continue
        }
        if ch == "\n" {
            i = i + 1
            line = line + 1
            column = 1
            continue
        }
        if ch == "/" && i + 1 < source_len && __host_char_at(source, i + 1) == "/" {
            i = i + 2
            column = column + 2
            while i < source_len && __host_char_at(source, i) != "\n" {
                i = i + 1
                column = column + 1
            }
            continue
        }
        if ch == "/" && i + 1 < source_len && __host_char_at(source, i + 1) == "*" {
			let comment_line = line
			let comment_column = column
            i = i + 2
            column = column + 2
            while i + 1 < source_len && !(__host_char_at(source, i) == "*" && __host_char_at(source, i + 1) == "/") {
                if __host_char_at(source, i) == "\n" {
                    line = line + 1
                    column = 1
                } else {
                    column = column + 1
                }
                i = i + 1
            }
            if i + 1 < source_len {
                i = i + 2
                column = column + 2
			} else {
				return lexer_error("SYNTAX", comment_line, comment_column, "unterminated block comment")
            }
            continue
        }

        let token_line = line
        let token_column = column
        if is_alpha(ch) {
            let start = i
            while i < source_len && is_ident_continue(__host_char_at(source, i)) {
                i = i + 1
                column = column + 1
            }
            let lexeme = __host_slice(source, start, i)
            output = append_token(output, keyword_kind(lexeme), lexeme, token_line, token_column)
            continue
        }
        if is_digit(ch) {
            let start = i
            while i < source_len && is_digit(__host_char_at(source, i)) {
                i = i + 1
                column = column + 1
            }
			if i + 1 < source_len && __host_char_at(source, i) == "." && is_digit(__host_char_at(source, i + 1)) {
				i = i + 1
				column = column + 1
				while i < source_len && is_digit(__host_char_at(source, i)) {
					i = i + 1
					column = column + 1
				}
			}
			if i < source_len && (__host_char_at(source, i) == "e" || __host_char_at(source, i) == "E") {
				let exponent_i = i
				let exponent_column = column
				i = i + 1
				column = column + 1
				if i < source_len && (__host_char_at(source, i) == "+" || __host_char_at(source, i) == "-") {
					i = i + 1
					column = column + 1
				}
				if i < source_len && is_digit(__host_char_at(source, i)) {
					while i < source_len && is_digit(__host_char_at(source, i)) {
						i = i + 1
						column = column + 1
					}
				} else {
					i = exponent_i
					column = exponent_column
				}
			}
            let lexeme = __host_slice(source, start, i)
            output = append_token(output, "NUMBER", lexeme, token_line, token_column)
            continue
        }
        if ch == "\"" {
            i = i + 1
            column = column + 1
            let start = i
            while i < source_len && __host_char_at(source, i) != "\"" && __host_char_at(source, i) != "\n" {
                if __host_char_at(source, i) == "\\" && i + 1 < source_len {
                    i = i + 2
                    column = column + 2
                } else {
                    i = i + 1
                    column = column + 1
                }
            }
			if i >= source_len || __host_char_at(source, i) != "\"" {
				return lexer_error("UNTERMINATED_STRING", token_line, token_column, "unterminated string literal")
			}
            let lexeme = __host_slice(source, start, i)
            output = append_token(output, "STRING", lexeme, token_line, token_column)
            if i < source_len && __host_char_at(source, i) == "\"" {
                i = i + 1
                column = column + 1
            }
            continue
        }

        var symbol = ch
        if i + 1 < source_len {
            let pair = __host_slice(source, i, i + 2)
            if pair == "==" || pair == "!=" || pair == "<=" || pair == ">=" || pair == "&&" || pair == "||" {
                symbol = pair
            }
        }
        output = append_token(output, symbol_kind(symbol), symbol, token_line, token_column)
		if symbol_kind(symbol) == "UNKNOWN" {
			return lexer_error("ILLEGAL_CHAR", token_line, token_column, "illegal character: " + symbol)
		}
        i = i + len(symbol)
        column = column + len(symbol)
    }
    return append_token(output, "EOF", "", line, column)
}

func main() int {
    let args = host_args()
    if len(args) != 3 {
        eprintln("usage: s_selfhost_lexer <input.s> <output.tokens>")
        return 2
    }
    let source = __host_read_to_string(args[1])
    let output = dump_tokens(source)
	if len(output) >= 6 && __host_slice(output, 0, 6) == "ERROR|" {
		__host_write_text_file(args[2], output)
		return 0
	}
    if __host_write_text_file(args[2], output) != 0 {
        return 1
    }
    return 0
}
