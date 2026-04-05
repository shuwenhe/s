package frontend

use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.vec.Vec
use std.result.Result

pub struct LexError {
    message: String,
    line: i32,
    column: i32,
}

pub struct Lexer {
    source: String,
    index: i32,
    line: i32,
    column: i32,
}

pub fn new_lexer(source: String) -> Lexer {
    Lexer {
        source: source,
        index: 0,
        line: 1,
        column: 1,
    }
}

impl Lexer {
    pub fn tokenize(mut self) -> Result[Vec[Token], LexError] {
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
                        TokenKind::Keyword
                    } else {
                        TokenKind::Ident
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
                    kind: TokenKind::Int,
                    value: self.read_number()?,
                    line: start_line,
                    column: start_column,
                })
                continue
            }

            if ch == "\"" {
                tokens.push(Token {
                    kind: TokenKind::String,
                    value: self.read_string()?,
                    line: start_line,
                    column: start_column,
                })
                continue
            }

            tokens.push(Token {
                kind: TokenKind::Symbol,
                value: self.read_symbol()?,
                line: start_line,
                column: start_column,
            })
        }

        tokens.push(Token {
            kind: TokenKind::Eof,
            value: "<eof>",
            line: self.line,
            column: self.column,
        })

        Result::Ok(tokens)
    }

    fn skip_ignored(mut self) -> Result[(), LexError] {
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

    fn read_identifier(mut self) -> Result[String, LexError] {
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

    fn read_number(mut self) -> Result[String, LexError] {
        var out = ""
        while !self.is_eof() {
            var ch = self.peek()?
            if !is_digit(ch) {
                break
            }
            out = out + self.advance()?
        }
        Result::Ok(out)
    }

    fn read_string(mut self) -> Result[String, LexError] {
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

    fn read_symbol(mut self) -> Result[String, LexError] {
        var multi = Vec[String] {
            "->",
            "=>",
            "==",
            "!=",
            "<=",
            ">=",
            "&&",
            "||",
            "..=",
            "..",
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

    fn match_text(self, text: String) -> bool {
        slice(self.source, self.index, self.index + len(text)) == text
    }

    fn peek(self) -> Result[String, LexError] {
        if self.is_eof() {
            return Result::Err(self.error("unexpected eof"))
        }
        Result::Ok(char_at(self.source, self.index))
    }

    fn advance(mut self) -> Result[String, LexError] {
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

    fn is_eof(self) -> bool {
        self.index >= len(self.source)
    }

    fn error(self, message: String) -> LexError {
        LexError {
            message: message,
            line: self.line,
            column: self.column,
        }
    }
}

pub fn is_whitespace(ch: String) -> bool {
    match ch {
        " " => true,
        "\t" => true,
        "\r" => true,
        "\n" => true,
        _ => false,
    }
}

pub fn is_digit(ch: String) -> bool {
    match ch {
        "0" => true,
        "1" => true,
        "2" => true,
        "3" => true,
        "4" => true,
        "5" => true,
        "6" => true,
        "7" => true,
        "8" => true,
        "9" => true,
        _ => false,
    }
}

pub fn is_ident_start(ch: String) -> bool {
    if ch == "_" {
        return true
    }
    is_ascii_alpha(ch)
}

pub fn is_ident_continue(ch: String) -> bool {
    is_ident_start(ch) || is_digit(ch)
}

pub fn is_ascii_alpha(ch: String) -> bool {
    match ch {
        "a" => true,
        "b" => true,
        "c" => true,
        "d" => true,
        "e" => true,
        "f" => true,
        "g" => true,
        "h" => true,
        "i" => true,
        "j" => true,
        "k" => true,
        "l" => true,
        "m" => true,
        "n" => true,
        "o" => true,
        "p" => true,
        "q" => true,
        "r" => true,
        "s" => true,
        "t" => true,
        "u" => true,
        "v" => true,
        "w" => true,
        "x" => true,
        "y" => true,
        "z" => true,
        "A" => true,
        "B" => true,
        "C" => true,
        "D" => true,
        "E" => true,
        "F" => true,
        "G" => true,
        "H" => true,
        "I" => true,
        "J" => true,
        "K" => true,
        "L" => true,
        "M" => true,
        "N" => true,
        "O" => true,
        "P" => true,
        "Q" => true,
        "R" => true,
        "S" => true,
        "T" => true,
        "U" => true,
        "V" => true,
        "W" => true,
        "X" => true,
        "Y" => true,
        "Z" => true,
        _ => false,
    }
}

pub fn is_single_symbol(ch: String) -> bool {
    match ch {
        "(" => true,
        ")" => true,
        "[" => true,
        "]" => true,
        "{" => true,
        "}" => true,
        "." => true,
        "," => true,
        ":" => true,
        ";" => true,
        "+" => true,
        "-" => true,
        "*" => true,
        "/" => true,
        "%" => true,
        "!" => true,
        "=" => true,
        "<" => true,
        ">" => true,
        "?" => true,
        "&" => true,
        "|" => true,
        _ => false,
    }
}
