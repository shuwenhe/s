package compile.internal.syntax
import (
    "compile.internal.ast"
    "std"
    "std.fs"
)
struct parse_error {
    string message
    int line
    int column
}

func read_source(string path) string {
    ""
}

func tokenize(string source) (string[], parse_error) {
    empty := string[]()
    return empty, parse_error { message: "tokenizer not connected", line: 0, column: 0 }
}

func parse_source(string source) (ast.source_file, parse_error) {
    empty := ast.source_file {}
    return empty, parse_error { message: "parser not connected", line: 0, column: 0 }
}

func parse_tokens(string[] tokens) (ast.source_file, parse_error) {
    empty := ast.source_file {}
    return empty, parse_error { message: "parser not connected", line: 0, column: 0 }
}

func dump_tokens_text(string[] tokens) string {
    ""
}

func dump_source_text(ast.source_file source) string {
    ""
}
