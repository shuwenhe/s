package s

use std.prelude.to_string
use std.vec.vec

enum token_kind {
    ident,
    int,
    string,
    keyword,
    symbol,
    eof,
}

struct token {
    token_kind kind
    string value
    int32 line
    int32 column
}

func token_kind_name(token_kind kind) string {
    switch kind {
        token_kind::ident : "ident",
        token_kind::int : "int",
        token_kind::string : "string",
        token_kind::keyword : "keyword",
        token_kind::symbol : "symbol",
        token_kind::eof : "eof",
    }
}

func dump_tokens(vec[token] tokens) string {

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
