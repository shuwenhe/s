package s

use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.vec.vec
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

impl lexer {
    func tokenize(mut self) result[vec[token], lex_error] {
        var tokens = vec[token]()
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
                    value: self.read_number()?,
                    line: start_line,
                    column: start_column,
                })
                continue
            }

            if ch == "\"" {
                tokens.push(token {
                    kind: token_kind::string,
                    value: self.read_string()?,
                    line: start_line,
                    column: start_column,
                })
                continue
            }

            tokens.push(token {
                kind: token_kind::symbol,
                value: self.read_symbol()?,
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

        result::ok(tokens)
    }

    func skip_ignored(mut self) result[(), lex_error] {
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

        result::ok(())
    }

    func read_identifier(mut self) result[string, lex_error] {
        var out = ""
        while !self.is_eof() {
            var ch = self.peek()?
            if !is_ident_continue(ch) {
                break
            }
            out = out + self.advance()?
        }
        result::ok(out)
    }

    func read_number(mut self) result[string, lex_error] {
        var out = ""
        while !self.is_eof() {
            var ch = self.peek()?
            if !is_number_continue(ch) {
                break
            }
            out = out + self.advance()?
        }
        result::ok(out)
    }

    func read_string(mut self) result[string, lex_error] {
        var out = self.advance()?
        while !self.is_eof() {
            var ch = self.advance()?
            out = out + ch
            if ch == "\\" {
                if self.is_eof() {
                    return result::err(self.error("unterminated escape sequence"))
                }
                out = out + self.advance()?
                continue
            }
            if ch == "\"" {
                return result::ok(out)
            }
        }
        result::err(self.error("unterminated string literal"))
    }

    func read_symbol(mut self) result[string, lex_error] {
        var multi = vec[string] {
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
                return result::ok(out)
            }
        }

        var ch = self.peek()?
        if is_single_symbol(ch) {
            return result::ok(self.advance()?)
        }

        result::err(self.error("unexpected character"))
    }

    func match_text(self, string text) bool {
        if self.index + len(text) > len(self.source) {
            return false
        }
        slice(self.source, self.index, self.index + len(text)) == text
    }

    func peek(self) result[string, lex_error] {
        if self.is_eof() {
            return result::err(self.error("unexpected eof"))
        }
        result::ok(char_at(self.source, self.index))
    }

    func advance(mut self) result[string, lex_error] {
        if self.is_eof() {
            return result::err(self.error("unexpected eof"))
        }

        var ch = char_at(self.source, self.index)
        self.index = self.index + 1

        if ch == "\n" {
            self.line = self.line + 1
            self.column = 1
        } else {
            self.column = self.column + 1
        }

        result::ok(ch)
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
        "?" : true,
        "&" : true,
        "|" : true,
        "^" : true,
        _ : false,
    }
}
