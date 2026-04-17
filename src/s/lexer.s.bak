package s

use std.prelude.charAt
use std.prelude.len
use std.prelude.slice
use std.vec.Vec
use std.result.Result

struct LexError {
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

func newLexer(string source) Lexer {
    Lexer {
        source: source,
        index: 0,
        line: 1,
        column: 1,
    }
}

impl Lexer {
    func tokenize(mut self) Result[Vec[Token], LexError] {
        var tokens = Vec[Token]()
        while !self.isEof() {
            self.skipIgnored()?
            if self.isEof() {
                break
            }

            var startLine = self.line
            var startColumn = self.column
            var ch = self.peek()?

            if isIdentStart(ch) {
                var value = self.readIdentifier()?
                var kind =
                    if isKeyword(value) {
                        TokenKind::Keyword
                    } else {
                        TokenKind::Ident
                    }
                tokens.push(Token {
                    kind: kind,
                    value: value,
                    line: startLine,
                    column: startColumn,
                })
                continue
            }

            if isDigit(ch) {
                tokens.push(Token {
                    kind: TokenKind::Int,
                    value: self.readNumber()?,
                    line: startLine,
                    column: startColumn,
                })
                continue
            }

            if ch == "\"" {
                tokens.push(Token {
                    kind: TokenKind::string,
                    value: self.readString()?,
                    line: startLine,
                    column: startColumn,
                })
                continue
            }

            tokens.push(Token {
                kind: TokenKind::Symbol,
                value: self.readSymbol()?,
                line: startLine,
                column: startColumn,
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

    func skipIgnored(mut self) Result[(), LexError] {
        while !self.isEof() {
            var ch = self.peek()?

            if isWhitespace(ch) {
                self.advance()?
                continue
            }

            if self.matchText("//") {
                while !self.isEof() && self.peek()? != "\n" {
                    self.advance()?
                }
                continue
            }

            if self.matchText("/*") {
                self.advance()?
                self.advance()?
                var depth = 1
                while depth > 0 {
                    if self.isEof() {
                        return err(self.error("unterminated block comment"))
                    }
                    if self.matchText("/*") {
                        depth = depth + 1
                        self.advance()?
                        self.advance()?
                        continue
                    }
                    if self.matchText("*/") {
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

    func readIdentifier(mut self) Result[string, LexError] {
        var out = ""
        while !self.isEof() {
            var ch = self.peek()?
            if !isIdentContinue(ch) {
                break
            }
            out = out + self.advance()?
        }
        Result::Ok(out)
    }

    func readNumber(mut self) Result[string, LexError] {
        var out = ""
        while !self.isEof() {
            var ch = self.peek()?
            if !isNumberContinue(ch) {
                break
            }
            out = out + self.advance()?
        }
        Result::Ok(out)
    }

    func readString(mut self) Result[string, LexError] {
        var out = self.advance()?
        while !self.isEof() {
            var ch = self.advance()?
            out = out + ch
            if ch == "\\" {
                if self.isEof() {
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

    func readSymbol(mut self) Result[string, LexError] {
        var multi = Vec[string] {
            "->",
            "=>",
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
            if self.matchText(symbol) {
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
        if isSingleSymbol(ch) {
            return Result::Ok(self.advance()?)
        }

        Result::Err(self.error("unexpected character"))
    }

    func matchText(self, string text) bool {
        if self.index + len(text) > len(self.source) {
            return false
        }
        slice(self.source, self.index, self.index + len(text)) == text
    }

    func peek(self) Result[string, LexError] {
        if self.isEof() {
            return Result::Err(self.error("unexpected eof"))
        }
        Result::Ok(charAt(self.source, self.index))
    }

    func advance(mut self) Result[string, LexError] {
        if self.isEof() {
            return Result::Err(self.error("unexpected eof"))
        }

        var ch = charAt(self.source, self.index)
        self.index = self.index + 1

        if ch == "\n" {
            self.line = self.line + 1
            self.column = 1
        } else {
            self.column = self.column + 1
        }

        Result::Ok(ch)
    }

    func isEof(self) bool {
        self.index >= len(self.source)
    }

    func error(self, string message) LexError {
        LexError {
            message: message,
            line: self.line,
            column: self.column,
        }
    }
}

func isWhitespace(string ch) bool {
    match ch {
        " " => true,
        "\t" => true,
        "\r" => true,
        "\n" => true,
        _ => false,
    }
}

func isDigit(string ch) bool {
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

func isNumberContinue(string ch) bool {
    isDigit(ch) || ch == "_"
}

func isIdentStart(string ch) bool {
    if ch == "_" {
        return true
    }
    isAsciiAlpha(ch)
}

func isIdentContinue(string ch) bool {
    isIdentStart(ch) || isDigit(ch)
}

func isAsciiAlpha(string ch) bool {
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

func isSingleSymbol(string ch) bool {
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
        "^" => true,
        _ => false,
    }
}
