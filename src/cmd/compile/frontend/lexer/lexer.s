package s
import (
    "std"
    "std.prelude"
    "std.result"
)

extern "intrinsic" func __host_byte_at(string text, int index) int;

struct lex_error {
    string message
    int line
    int column
}

struct lexer {
    string source
    int index
    int line
    int column
}

func new_lexer(string source) lexer {
    return lexer {
        source: source, index: 0, line: 1, column: 1,
    }
}

func (lexer* self) tokenize() (token[], lex_error) {
    token[] tokens = token[]()
    for !self.is_eof() {
        self.skip_ignored()
        if self.is_eof() {
            break
        }
        int start_line = self.line
        int start_column = self.column
        string ch = self.peek()
        if is_ident_start(ch) {
            string value = self.read_identifier()
            token_kind kind = if is_keyword(value) {
                token_kind::keyword
            } else {
                token_kind::ident
            }
            tokens.push(token {
                kind: kind, value: value, line: start_line, column: start_column,
            })
            continue
        }
        if is_digit(ch) {
            tokens.push(token {
                kind: token_kind::int, value: self.read_number(), line: start_line, column: start_column,
            })
            continue
        }
        if ch == "\"" {
            tokens.push(token {
                kind: token_kind::string, value: self.read_string(), line: start_line, column: start_column,
            })
            continue
        }
        if ch == '(' || ch == ')' {
            tokens.push(token {
                kind: token_kind::symbol, value: self.read_symbol(), line: start_line, column: start_column,
            })
            continue
        }
        tokens.push(token {
            kind: token_kind::symbol, value: self.read_symbol(), line: start_line, column: start_column,
        })
    }
    tokens.push(token {
        kind: token_kind::eof,
        value: "<eof>", line: self.line, column: self.column,
    })
    return tokens
}

func (lexer* self) skip_ignored() ((), lex_error) {
    for !self.is_eof() {
        string ch = self.peek()
        if is_whitespace(ch) {
            self.advance()
            continue
        }
        if self.match_text("//") {
            for !self.is_eof() && self.peek() != "\n" {
                self.advance()
            }
            continue
        }
        if self.match_text("/*") {
            depth := 1
            self.advance()
            self.advance()
            for !self.is_eof() && depth > 0 {
                if self.match_text("*/") {
                    depth = depth - 1
                    self.advance()
                    self.advance()
                    if depth == 0 {
                        break
                    }
                    continue
                }
                if self.match_text("/*") {
                    depth = depth + 1
                }
                self.advance()
            }
            continue
        }
        break
    }
    return (), lex_error{}
}

func (lexer* self) read_identifier() (string, lex_error) {
    string out = ""
    for !self.is_eof() {
        string ch = self.peek()
        if !is_ident_continue(ch) {
            break
        }
        out = out + self.advance()
    }
    return out
}

func (lexer* self) read_number() (string, lex_error) {
    string out = ""
    for !self.is_eof() {
        string ch = self.peek()
        if !is_number_continue(ch) {
            break
        }
        out = out + self.advance()
    }
    return out
}

func (lexer* self) read_string() (string, lex_error) {
    string out = self.advance()
    for !self.is_eof() {
        ch := self.advance()
        out = out + ch
        if ch == "\\" {
            if self.is_eof() {
                return self.error("unterminated escape sequence")
            }
            ch = self.advance()
            continue
        }
        if ch == "\"" {
            return out
        }
    }
    return self.error("unterminated string literal")
}

func (lexer* self) read_symbol() (string, lex_error) {
    string[] multi = string[] {
        "->",
        ":",
        "==",
        "!=",
        "<=",
        ">=",
        "&&",
        "||",
        "++",
        "..=",
        "..",
        "<<",
        ">>",
        "::",
    }
    multi_index := 0
    for multi_index < std.prelude.len(multi) {
        symbol := multi[multi_index]
        if self.match_text(symbol) {
            string out = ""
            int count = std.prelude.len(symbol)
            int i = 0
            for i < count {
                out = out + self.advance()
                i = i + 1
            }
            return out
        }
        multi_index = multi_index + 1
    }
    string ch = self.peek()
    if is_single_symbol(ch) {
        return self.advance()
    }
    self.error("unexpected character")
}

func (lexer* self) match_text(string text) bool {
    if self.index + std.prelude.len(text) > std.prelude.len(self.source) {
        return false
    }
    return std.prelude.slice(self.source, self.index, self.index + std.prelude.len(text)) == text
}

func (lexer* self) peek() (string, lex_error) {
    if self.is_eof() {
        return self.error("unexpected eof")
    }
    return std.prelude.char_at(self.source, self.index)
}

func (lexer* self) advance() (string, lex_error) {
    if self.is_eof() {
        return self.error("unexpected eof")
    }
    string ch = std.prelude.char_at(self.source, self.index)
    self.index = self.index + 1
    if ch == "\n" {
        self.line = self.line + 1
        self.column = 1
    } else {
        self.column = self.column + 1
    }
    return ch
}

func (lexer* self) is_eof() bool {
    return self.index >= std.prelude.len(self.source)
}

func (lexer* self) error(string message) lex_error {
    return lex_error {
        message: message, line: self.line, column: self.column,
    }
}

func is_whitespace(string ch) bool {
    switch ch {
        " " : true,
        "\t" : true,
        "\r" : true,
        "\n" : true,
        _ : false,
    }
}

func is_digit(string ch) bool {
    switch ch {
        "0" : true,
        "1" : true,
        "2" : true,
        "3" : true,
        "4" : true,
        "5" : true,
        "6" : true,
        "7" : true,
        "8" : true,
        "9" : true,
        _ : false,
    }
}

func is_number_continue(string ch) bool {
    is_digit(ch) || ch == "_"
}

func is_ident_start(string ch) bool {
    if ch == "_" {
        return true
    }
    is_ascii_alpha(ch)
}

func is_ident_continue(string ch) bool {
    is_ident_start(ch) || is_digit(ch)
}

func is_ascii_alpha(string ch) bool {
    switch ch {
        "a" : true,
        "b" : true,
        "c" : true,
        "d" : true,
        "e" : true,
        "f" : true,
        "g" : true,
        "h" : true,
        "i" : true,
        "j" : true,
        "k" : true,
        "l" : true,
        "m" : true,
        "n" : true,
        "o" : true,
        "p" : true,
        "q" : true,
        "r" : true,
        "s" : true,
        "t" : true,
        "u" : true,
        "v" : true,
        "w" : true,
        "x" : true,
        "y" : true,
        "z" : true,
        "a" : true,
        "b" : true,
        "c" : true,
        "d" : true,
        "e" : true,
        "f" : true,
        "g" : true,
        "h" : true,
        "i" : true,
        "j" : true,
        "k" : true,
        "l" : true,
        "m" : true,
        "n" : true,
        "o" : true,
        "p" : true,
        "q" : true,
        "r" : true,
        "s" : true,
        "t" : true,
        "u" : true,
        "v" : true,
        "w" : true,
        "x" : true,
        "y" : true,
        "z" : true,
        _ : false,
    }
}

func is_single_symbol(string ch) bool {
    switch ch {
        "(" : true,
        ")" : true,
        "[" : true,
        "]" : true,
        "{" : true,
        "}" : true,
        "." : true,
        "," : true,
        ":" : true,
        ";" : true,
        "+" : true,
        "-" : true,
        "*" : true,
        "/" : true,
        "%" : true,
        "!" : true,
        "=" : true,
        "<" : true,
        ">" : true,
        "" : true,
        "&" : true,
        "|" : true,
        "^" : true,
        _ : false,
    }
}

func is_keyword(string value) bool {
    return value == "func"
}

func selfhost_dump_is_digit(string ch) bool {
    return ch >= "0" && ch <= "9"
}

func selfhost_dump_is_alpha(string ch) bool {
    return (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch == "_"
}

func selfhost_dump_is_ident_continue(string ch) bool {
    return selfhost_dump_is_alpha(ch) || selfhost_dump_is_digit(ch)
}

func selfhost_dump_keyword_kind(string text) string {
    if text == "func" { return "FN" }
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

func selfhost_dump_symbol_kind(string text) string {
    if text == "+" { return "+" }
    if text == "-" { return "-" }
    if text == "*" { return "*" }
    if text == "/" { return "/" }
    if text == "%" { return "%" }
    if text == "!" { return "!" }
    if text == "=" { return "=" }
    if text == ":=" { return ":=" }
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
    return "unknown"
}

func selfhost_dump_digit_text(int value) string {
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

func selfhost_dump_int_text(int value) string {
    if value < 10 { return selfhost_dump_digit_text(value) }
    return selfhost_dump_int_text(value / 10) + selfhost_dump_digit_text(value % 10)
}

func selfhost_dump_hex_digit(int value) string {
    if value < 10 { return selfhost_dump_digit_text(value) }
    if value == 10 { return "a" }
    if value == 11 { return "b" }
    if value == 12 { return "c" }
    if value == 13 { return "d" }
    if value == 14 { return "e" }
    return "f"
}

func selfhost_dump_hex_text(string text) string {
    string output = ""
    int index = 0
    for index < len(text) {
        int value = __host_byte_at(text, index)
        output = output + selfhost_dump_hex_digit(value / 16) + selfhost_dump_hex_digit(value % 16)
        index = index + 1
    }
    return output
}

func selfhost_dump_lexer_error(string code, int line, int column, string message) string {
    return "ERROR|" + code + "|" + selfhost_dump_int_text(line) + "|" + selfhost_dump_int_text(column) + "|" + message + "\n"
}

func selfhost_dump_append_token(string output, string kind, string lexeme, int line, int column) string {
    return output + kind + "|" + selfhost_dump_hex_text(lexeme) + "|" + selfhost_dump_int_text(line) + "|" + selfhost_dump_int_text(column) + "\n"
}

func selfhost_dump_tokens(string source) string {
    string output = ""
    int i = 0
    int line = 1
    int column = 1
    int source_len = len(source)
    for i < source_len {
        string ch = std.prelude.char_at(source, i)
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
        if ch == "/" && i + 1 < source_len && std.prelude.char_at(source, i + 1) == "/" {
            i = i + 2
            column = column + 2
            for i < source_len && std.prelude.char_at(source, i) != "\n" {
                i = i + 1
                column = column + 1
            }
            continue
        }
        if ch == "/" && i + 1 < source_len && std.prelude.char_at(source, i + 1) == "*" {
			int comment_line = line
			int comment_column = column
            i = i + 2
            column = column + 2
            for i + 1 < source_len && !(std.prelude.char_at(source, i) == "*" && std.prelude.char_at(source, i + 1) == "/") {
                if std.prelude.char_at(source, i) == "\n" {
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
				return selfhost_dump_lexer_error("SYNTAX", comment_line, comment_column, "unterminated block comment")
            }
            continue
        }
        int token_line = line
        int token_column = column
        if selfhost_dump_is_alpha(ch) {
            int start = i
            for i < source_len && selfhost_dump_is_ident_continue(std.prelude.char_at(source, i)) {
                i = i + 1
                column = column + 1
            }
            string lexeme = std.prelude.slice(source, start, i)
            output = selfhost_dump_append_token(output, selfhost_dump_keyword_kind(lexeme), lexeme, token_line, token_column)
            continue
        }
        if selfhost_dump_is_digit(ch) {
            int start = i
            for i < source_len && selfhost_dump_is_digit(std.prelude.char_at(source, i)) {
                i = i + 1
                column = column + 1
            }
			if i + 1 < source_len && std.prelude.char_at(source, i) == "." && selfhost_dump_is_digit(std.prelude.char_at(source, i + 1)) {
				i = i + 1
				column = column + 1
				for i < source_len && selfhost_dump_is_digit(std.prelude.char_at(source, i)) {
					i = i + 1
					column = column + 1
				}
			}
			if i < source_len && (std.prelude.char_at(source, i) == "e" || std.prelude.char_at(source, i) == "E") {
				int exponent_i = i
				int exponent_column = column
				i = i + 1
				column = column + 1
				if i < source_len && (std.prelude.char_at(source, i) == "+" || std.prelude.char_at(source, i) == "-") {
					i = i + 1
					column = column + 1
				}
				if i < source_len && selfhost_dump_is_digit(std.prelude.char_at(source, i)) {
					for i < source_len && selfhost_dump_is_digit(std.prelude.char_at(source, i)) {
						i = i + 1
						column = column + 1
					}
				} else {
					i = exponent_i
					column = exponent_column
				}
			}
            string lexeme = std.prelude.slice(source, start, i)
            output = selfhost_dump_append_token(output, "NUMBER", lexeme, token_line, token_column)
            continue
        }
        if ch == "\"" {
            i = i + 1
            column = column + 1
            int start = i
            for i < source_len && std.prelude.char_at(source, i) != "\"" && std.prelude.char_at(source, i) != "\n" {
                if std.prelude.char_at(source, i) == "\\" && i + 1 < source_len {
                    i = i + 2
                    column = column + 2
                } else {
                    i = i + 1
                    column = column + 1
                }
            }
			if i >= source_len || std.prelude.char_at(source, i) != "\"" {
				return selfhost_dump_lexer_error("UNTERMINATED_STRING", token_line, token_column, "unterminated string literal")
			}
            string lexeme = std.prelude.slice(source, start, i)
            output = selfhost_dump_append_token(output, "STRING", lexeme, token_line, token_column)
            if i < source_len && std.prelude.char_at(source, i) == "\"" {
                i = i + 1
                column = column + 1
            }
            continue
        }
        string symbol = ch
        if i + 1 < source_len {
            string pair = std.prelude.slice(source, i, i + 2)
            if pair == ":=" || pair == "==" || pair == "!=" || pair == "<=" || pair == ">=" || pair == "&&" || pair == "||" {
                symbol = pair
            }
        }
        output = selfhost_dump_append_token(output, selfhost_dump_symbol_kind(symbol), symbol, token_line, token_column)
		if selfhost_dump_symbol_kind(symbol) == "unknown" {
			return selfhost_dump_lexer_error("ILLEGAL_CHAR", token_line, token_column, "illegal character: " + symbol)
		}
        i = i + len(symbol)
        column = column + len(symbol)
    }
    return selfhost_dump_append_token(output, "EOF", "", line, column)
}
