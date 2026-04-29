package compile.internal.syntax

use std.fs.read_to_string
use std.result.result
use std.vec.vec
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

func read_source(string path) result[string, syntax_error] {
    switch read_to_string(path) {
        result::ok(source) : result::ok(source),
        result::err(err) : result::err(syntax_error {
            message: "failed to read source file: " + path + ": " + err.message,
            line: 0,
            column: 0,
        }),
    }
}

func tokenize(string source) result[vec[token], syntax_error] {
    switch new_lexer(source).tokenize() {
        result::ok(tokens) : result::ok(tokens),
        result::err(err) : result::err(syntax_error {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func parse_source(string source) result[source_file, syntax_error] {
    let tokens = tokenize(source)?
    parse_tokens(tokens)
}

func parse_tokens(vec[token] tokens) result[source_file, syntax_error] {
    switch parse_tokens(tokens) {
        result::ok(ast) : result::ok(ast),
        result::err(err) : result::err(syntax_error {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func dump_tokens_text(vec[token] tokens) string {
    dump_tokens(tokens)
}

func dump_source_text(source_file source) string {
    dump_source_file(source)
}
