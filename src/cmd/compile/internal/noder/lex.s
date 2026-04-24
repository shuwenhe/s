package compile.internal.noder

use std.result.result
use std.vec.vec

func classify_token(string token) string {
    if token == "package" || token == "use" || token == "func" || token == "struct" || token == "enum" || token == "trait" || token == "impl" || token == "const" {
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

func lex_source(source_unit unit) result[vec[token_item], noder_error] {
    var out = vec[token_item]()
    var lines = split_lines(unit.text)
    var li = 0
    while li < lines.len() {
        var line = lines[li]
        var trimmed = trim_spaces(line)
        if starts_with(trimmed, "//") {
            li = li + 1
            continue
        }
        var words = split_words(line)
        var wi = 0
        while wi < words.len() {
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
    result::ok(out)
}
