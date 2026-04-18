package s

use std.prelude.to_string
use std.vec.Vec

enum token_kind {
    Ident,
    Int,
    string,
    Keyword,
    Symbol,
    Eof,
}

struct Token {
    token_kind kind,
    string value,
    int32 line,
    int32 column,
}

func token_kind_name(token_kind kind) string {
    switch kind {
        token_kind::Ident : "IDENT",
        token_kind::Int : "INT",
        token_kind::string : "STRING",
        token_kind::Keyword : "KEYWORD",
        token_kind::Symbol : "SYMBOL",
        token_kind::Eof : "EOF",
    }
}

func dump_tokens(Vec[Token] tokens) string {
    // Golden tests depend on this exact one-token-per-line format.
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

func is_keyword(string text) bool {
    switch text {
        "package" : true,
        "use" : true,
        "as" : true,
        "pub" : true,
        "func" : true,
        "let" : true,
        "var" : true,
        "const" : true,
        "static" : true,
        "struct" : true,
        "enum" : true,
        "trait" : true,
        "impl" : true,
        "for" : true,
        "if" : true,
        "else" : true,
        "while" : true,
        "switch" : true,
        "return" : true,
        "break" : true,
        "continue" : true,
        "true" : true,
        "false" : true,
        "unsafe" : true,
        "extern" : true,
        "mut" : true,
        "where" : true,
        "in" : true,
        _ : false,
    }
}
