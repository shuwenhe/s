package frontend

use std.prelude.to_string
use std.vec.Vec

pub enum TokenKind {
    Ident,
    Int,
    String,
    Keyword,
    Symbol,
    Eof,
}

pub struct Token {
    kind: TokenKind,
    value: String,
    line: i32,
    column: i32,
}

pub fn token_kind_name(kind: TokenKind) -> String {
    match kind {
        TokenKind::Ident => "IDENT",
        TokenKind::Int => "INT",
        TokenKind::String => "STRING",
        TokenKind::Keyword => "KEYWORD",
        TokenKind::Symbol => "SYMBOL",
        TokenKind::Eof => "EOF",
    }
}

pub fn dump_tokens(tokens: Vec[Token]) -> String {
    let out = ""
    for token in tokens {
        if out != "" {
            out = out + "\n"
        }
        out =
            out
            + to_string(token.line)
            + ":"
            + to_string(token.column)
            + " "
            + token_kind_name(token.kind)
            + " "
            + token.value
    }
    out
}

pub fn is_keyword(text: String) -> bool {
    match text {
        "package" => true,
        "use" => true,
        "as" => true,
        "fn" => true,
        "let" => true,
        "var" => true,
        "const" => true,
        "static" => true,
        "struct" => true,
        "enum" => true,
        "trait" => true,
        "impl" => true,
        "for" => true,
        "if" => true,
        "else" => true,
        "while" => true,
        "match" => true,
        "return" => true,
        "break" => true,
        "continue" => true,
        "true" => true,
        "false" => true,
        "unsafe" => true,
        "extern" => true,
        "mut" => true,
        "where" => true,
        "in" => true,
        _ => false,
    }
}
