package slatec.lexer

use std.option.Option
use std.result.Result
use std.vec.Vec

enum TokenKind {
    Ident,
    Keyword,
    String,
    Symbol,
    Eof,
}

struct Token {
    TokenKind kind,
    String value,
    i32 line,
    i32 column,
}

struct LexError {
    String message,
    i32 line,
    i32 column,
}

struct Lexer {
    String source,
    i32 index,
    i32 line,
    i32 column,
}

func new_lexer(String source) -> Lexer {
    Lexer {
        source: source,
        index: 0,
        line: 1,
        column: 1,
    }
}

impl Lexer {
    func tokenize(mut self) -> Result[Vec[Token], LexError] {
        var tokens = Vec[Token]()

        // Bootstrap MVP:
        // This S version intentionally mirrors the Python lexer shape first.
        // It is the self-hosted source of truth, not yet the executable path.

        tokens.push(Token {
            kind: TokenKind::Eof,
            value: "",
            line: self.line,
            column: self.column,
        })
        Result::Ok(tokens)
    }
}

