package compile.internal.syntax
import (
    "compile.internal.ast"
    "std"
    "std.fs"
    "std.result"
    "std.prelude"
)
struct syntax_error {
    string message
    int line
    int column
}

func read_source(string path) string {
    value := std.fs.read_to_string(path)
    switch value { std.result.result.ok(text): text, std.result.result.err(_): "", }
}

func tokenize(string source) (string[], syntax_error) {
    state := canonical_advance(canonical_parser { source: source, position: 0, line: 1, token_line: 1, token: "", error: "" })
    tokens := string[]()
    for state.error == "" && state.token != "" {
        tokens = append(tokens, state.token)
        state = canonical_advance(state)
    }
    if state.error != "" { return string[](), syntax_error { message: state.error, line: state.token_line, column: 1 } }
    return tokens, syntax_error { message: "", line: 0, column: 0 }
}

func parse_source(string source) (source_file, syntax_error) {
    return canonical_parse(source)
}

func parse_source_status(string source) int {
    parsed, error := parse_source(source)
    if error.message != "" { return 1 }
    return 0
}

func contains_source_text(string source, string needle) bool {
    if needle == "" { return true }
    i := 0
    for i + len(needle) <= len(source) {
        if std.prelude.prelude_slice(source, i, i + len(needle)) == needle { return true }
        i = i + 1
    }
    return false
}

func parse_tokens(string[] tokens) (source_file, syntax_error) {
    return parse_source(dump_tokens_text(tokens))
}

func dump_tokens_text(string[] tokens) string {
    output := ""
    i := 0
    for i < len(tokens) { output = output + tokens[i] + " "; i = i + 1 }
    return output
}

func dump_source_text(compile.internal.ast.source_file source) string {
    return compile.internal.ast.dump_source_file(source)
}
