package frontend

use std.prelude.to_string
use std.vec.Vec

enum TokenKind {
    Ident,
    Int,
    String,
    Keyword,
    Symbol,
    Eof,
}

struct Token {
    TokenKind kind,
    String value,
    i32 line,
    i32 column,
}

func token_kind_name(TokenKind kind) -> String {
    match kind {
        TokenKind::Ident => "IDENT",
        TokenKind::Int => "INT",
        TokenKind::String => "STRING",
        TokenKind::Keyword => "KEYWORD",
        TokenKind::Symbol => "SYMBOL",
        TokenKind::Eof => "EOF",
    }
}

func dump_tokens(Vec[Token] tokens) -> String {
    var out = ""
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

func is_keyword(String text) -> bool {
    match text {
        "package" => true,
        "use" => true,
        "as" => true,
        "func" => true,
        "var" => true,
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
