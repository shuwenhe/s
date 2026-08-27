package compile.internal.noder
use std.result.result
use std.slices

func classify_token(string token) string {
    if token == "package" || token == "use" || token == "func" || token == "struct" || token == "enum" || token == "trait" || token == "const" {
        return "keyword"
    }
    if token == "{" || token == "}" || token == "(" || token == ")" || token == ":" || token == ";" || token == "," {
        return "symbol"
    }
    if starts_with(token, "\"") {
        return "string"
    }
    "ident"
}

func lex_source(source_unit unit) (token_item[], noder_error) {
    out := token_item[]()
    lines := split_lines(unit.text)
    li := 0
    for li < len(lines) {
        line := lines[li]
        trimmed := trim_spaces(line)
        if starts_with(trimmed, "
            li = li + 1
            continue
        }
        words := split_words(line)
        wi := 0
        for wi < len(words) {
            out.push(token_item {
                kind: classify_token(words[wi]),
                text: words[wi],
                line: li + 1,
                column: 1,
            })
            wi = wi + 1
        }
        li = li + 1
    }
    out
}
