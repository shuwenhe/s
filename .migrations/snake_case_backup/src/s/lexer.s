package s

use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.vec.Vec
use std.result.Result

struct lex_error {
    string message,
    int32 line,
    int32 column,
}

struct Lexer {
    string source,
    int32 index,
    int32 line,
    int32 column,
}

func new_lexer(string source) Lexer {
    Lexer {
        source: source,
        index: 0,
        line: 1,
        column: 1,
    }
}

impl Lexer {
    func tokenize(mut self) Result[Vec[Token], lex_error] {
        var tokens = Vec[Token]()
        while !self.is_eof() {
            self.skip_ignored()?
            if self.is_eof() {
                break
            }

            var start_line = self.line
            var start_column = self.column
            var ch = self.peek()?

            if is_ident_start(ch) {
                var value = self.read_identifier()?
                var kind =
                    if is_keyword(value) {
                        token_kind::Keyword
                    } else {
                        token_kind::Ident
                    }
                tokens.push(Token {
                    kind: kind,
                    value: value,
                    line: start_line,
                    column: start_column,
                })
                continue
            }

            if is_digit(ch) {
                tokens.push(Token {
                    kind: token_kind::Int,
                    value: self.read_number()?,
                    line: start_line,
                    column: start_column,
                })
                continue
            }

            if ch == "\"" {
                tokens.push(Token {
                    kind: token_kind::string,
                    value: self.read_string()?,
                    line: start_line,
                    column: start_column,
                })
                continue
            }

            tokens.push(Token {
                kind: token_kind::Symbol,
                value: self.read_symbol()?,
                line: start_line,
                column: start_column,
            })
        }

        tokens.push(Token {
            kind: token_kind::Eof,
            value: "<eof>",
            line: self.line,
            column: self.column,
        })

        Result::Ok(tokens)
    }

    func skip_ignored(mut self) Result[(), lex_error] {
        while !self.is_eof() {
            var ch = self.peek()?

            if is_whitespace(ch) {
                self.advance()?
                continue
            }

            if self.match_text("//") {
                while !self.is_eof() && self.peek()? != "\n" {
                    self.advance()?
                }
                continue
            }

            if self.match_text("/*") {
                self.advance()?
                self.advance()?
                var depth = 1
                while depth > 0 {
                    if self.is_eof() {
                        return err(self.error("unterminated block comment"))
                    }
                    if self.match_text("/*") {
                        depth = depth + 1
                        self.advance()?
                        self.advance()?
                        continue
                    }
                    if self.match_text("*/") {
                        depth = depth - 1
                        self.advance()?
                        self.advance()?
                        continue
                    }
                    self.advance()?
                }
                continue
            }

            break
        }

        Result::Ok(())
    }

    func read_identifier(mut self) Result[string, lex_error] {
        var out = ""
        while !self.is_eof() {
            var ch = self.peek()?
            if !is_ident_continue(ch) {
                break
            }
            out = out + self.advance()?
        }
        Result::Ok(out)
    }

    func read_number(mut self) Result[string, lex_error] {
        var out = ""
        while !self.is_eof() {
            var ch = self.peek()?
            if !is_number_continue(ch) {
                break
            }
            out = out + self.advance()?
        }
        Result::Ok(out)
    }

    func read_string(mut self) Result[string, lex_error] {
        var out = self.advance()?
        while !self.is_eof() {
            var ch = self.advance()?
            out = out + ch
            if ch == "\\" {
                if self.is_eof() {
                    return Result::Err(self.error("unterminated escape sequence"))
                }
                out = out + self.advance()?
                continue
            }
            if ch == "\"" {
                return Result::Ok(out)
            }
        }
        Result::Err(self.error("unterminated string literal"))
    }

    func read_symbol(mut self) Result[string, lex_error] {
        var multi = Vec[string] {
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
            ":=",
            "<<",
            ">>",
            "::",
        }

        for symbol in multi {
            if self.match_text(symbol) {
                var out = ""
                var count = len(symbol)
                var i = 0
                while i < count {
                    out = out + self.advance()?
                    i = i + 1
                }
                return Result::Ok(out)
            }
        }

        var ch = self.peek()?
        if is_single_symbol(ch) {
            return Result::Ok(self.advance()?)
        }

        Result::Err(self.error("unexpected character"))
    }

    func match_text(self, string text) bool {
        if self.index + len(text) > len(self.source) {
            return false
        }
        slice(self.source, self.index, self.index + len(text)) == text
    }

    func peek(self) Result[string, lex_error] {
        if self.is_eof() {
            return Result::Err(self.error("unexpected eof"))
        }
        Result::Ok(char_at(self.source, self.index))
    }

    func advance(mut self) Result[string, lex_error] {
        if self.is_eof() {
            return Result::Err(self.error("unexpected eof"))
        }

        var ch = char_at(self.source, self.index)
        self.index = self.index + 1

        if ch == "\n" {
            self.line = self.line + 1
            self.column = 1
        } else {
            self.column = self.column + 1
        }

        Result::Ok(ch)
    }

    func is_eof(self) bool {
        self.index >= len(self.source)
    }

    func error(self, string message) lex_error {
        lex_error {
            message: message,
            line: self.line,
            column: self.column,
        }
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
        "A" : true,
        "B" : true,
        "C" : true,
        "D" : true,
        "E" : true,
        "F" : true,
        "G" : true,
        "H" : true,
        "I" : true,
        "J" : true,
        "K" : true,
        "L" : true,
        "M" : true,
        "N" : true,
        "O" : true,
        "P" : true,
        "Q" : true,
        "R" : true,
        "S" : true,
        "T" : true,
        "U" : true,
        "V" : true,
        "W" : true,
        "X" : true,
        "Y" : true,
        "Z" : true,
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
        "?" : true,
        "&" : true,
        "|" : true,
        "^" : true,
        _ : false,
    }
}
