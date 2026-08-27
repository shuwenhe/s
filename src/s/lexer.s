package s
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.slices
use std.result.result

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
    lexer {
        source: source,
        index: 0,
        line: 1,
        column: 1,
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
                kind: kind,
                value: value,
                line: start_line,
                column: start_column,
            })
            continue
        }
        if is_digit(ch) {
            tokens.push(token {
                kind: token_kind::int,
                value: self.read_number(),
                line: start_line,
                column: start_column,
            })
            continue
        }
        if ch == "\"" {
            tokens.push(token {
                kind: token_kind::string,
                value: self.read_string(),
                line: start_line,
                column: start_column,
            })
            continue
        }
        if ch == '(' || ch == ')' {
            tokens.push(token {
                kind: token_kind::symbol,
                value: self.read_symbol(),
                line: start_line,
                column: start_column,
            })
            continue
        }
        tokens.push(token {
            kind: token_kind::symbol,
            value: self.read_symbol(),
            line: start_line,
            column: start_column,
        })
        }
        tokens.push(token {
            kind: token_kind::eof,
            value: "<eof>",
            line: self.line,
            column: self.column,
        })
        tokens
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
            self.advance()
            self.advance()
            int depth = 1
            for depth > 0 {
                if self.is_eof() {
                    (), lex_error empty
                    return empty, lex_error { message: "unterminated block comment", line: self.line, column: self.column }
                }
                if self.match_text("/*") {
                    depth = depth + 1
                    self.advance()
                    self.advance()
                    continue
                }
                if self.match_text("*/") {
                    depth = depth - 1
                    self.advance()
                    self.advance()
                    continue
                }
                self.advance()
            }
            continue
        }
        break
    }
    (), lex_error empty
    return empty
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
    out
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
    out
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
            string ch = self.advance()
            continue
        }
        if ch == "\"" {
            return out
        }
    }
    self.error("unterminated string literal")
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
    for symbol in multi {
        if self.match_text(symbol) {
            string out = ""
            int count = len(symbol)
            int i = 0
            for i < count {
                out = out + self.advance()
                i = i + 1
            }
            return out
        }
    }
    string ch = self.peek()
    if is_single_symbol(ch) {
        return self.advance()
    }
    self.error("unexpected character")
}

func (lexer* self) match_text(string text) bool {
    if self.index + len(text) > len(self.source) {
        return false
    }
    slice(self.source, self.index, self.index + len(text)) == text
}

func (lexer* self) peek() (string, lex_error) {
    if self.is_eof() {
        return self.error("unexpected eof")
    }
    char_at(self.source, self.index)
}

func (lexer* self) advance() (string, lex_error) {
    if self.is_eof() {
        return self.error("unexpected eof")
    }
    string ch = char_at(self.source, self.index)
    self.index = self.index + 1
    if ch == "\n" {
        self.line = self.line + 1
        self.column = 1
    } else {
        self.column = self.column + 1
    }
    ch
}

func (lexer* self) is_eof() bool {
    self.index >= len(self.source)
}

func (lexer* self) error(string message) lex_error {
    lex_error {
        message: message,
        line: self.line,
        column: self.column,
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
