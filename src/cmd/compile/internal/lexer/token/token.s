package s
import (
    "std"
    "std.prelude"
)

enum token_kind {
    ident,
    int,
    str,
    keyword,
    symbol,
    eof,
}

struct token {
    kind token_kind
    string value
    int line
    int column
}

func token_kind_name(token_kind kind) string {
    if kind == token_kind.ident { return "ident" }
    if kind == token_kind.int { return "int" }
    if kind == token_kind.str { return "string" }
    if kind == token_kind.keyword { return "keyword" }
    if kind == token_kind.symbol { return "symbol" }
    if kind == token_kind.eof { return "eof" }
    return ""
}

func dump_tokens(token[] tokens) string {
    out := ""
    _for_idx_31 := 0
    while _for_idx_31 < len(tokens) {
        token := tokens[_for_idx_31]
        if out != "" {
            out = out + "\n"
        }
        out =
            out
            + std.prelude.to_string(token.line)
            + ":"
            + std.prelude.to_string(token.column)
            + " "
            + token_kind_name(token.kind)
            + " "
            + token.value
        _for_idx_31 = _for_idx_31 + 1
    }
    out
}

func is_keyword(string text) bool {
    if text == "package" || text == "use" || text == "as" || text == "pub" || text == "func" || text == "const" || text == "var" || text == "static" || text == "struct" || text == "enum" || text == "trait" || text == "for" || text == "if" || text == "else" || text == "while" || text == "switch" || text == "select" || text == "case" || text == "default" || text == "return" || text == "break" || text == "continue" || text == "sroutine" || text == "true" || text == "false" || text == "nil" || text == "unsafe" || text == "extern" || text == "where" || text == "in" { return true }
    return false
}
