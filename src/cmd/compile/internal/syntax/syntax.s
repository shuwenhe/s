package compile.internal.syntax
use std.fs.read_to_string
use std.result.result
use std.slices
use s.source_file
use s.token
use s.dump_source_file
use s.dump_tokens
use s.new_lexer
use s.parse_tokens
struct syntax_error {
    string message
    int line
    int column
}

func read_source(string path) (string, syntax_error) {
    switch read_to_string(path) {
        source : source,
        err : syntax_error {
            message: "failed to read source file: " + path + ": " + err.message, line 0, column 0,
        },
    }
}

func tokenize(string source) (token[], syntax_error) {
    switch new_lexer(source).tokenize() {
        tokens : tokens,
        err : syntax_error {
            message: err.message, line err.line, column err.column,
        },
    }
}

func parse_source(string source) (source_file, syntax_error) {
    tokens := tokenize(source)?
    parse_tokens(tokens)
}

func parse_tokens(token[] tokens) (source_file, syntax_error) {
    switch parse_tokens(tokens) {
        ast : ast,
        err : syntax_error {
            message: err.message, line err.line, column err.column,
        },
    }
}

func dump_tokens_text(token[] tokens) string {
    dump_tokens(tokens)
}

func dump_source_text(source_file source) string {
    dump_source_file(source)
}
