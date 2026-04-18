package compile.internal.syntax

use std.fs.read_to_string
use std.result.Result
use std.vec.Vec
use s.source_file
use s.Token
use s.dump_source_file
use s.dump_tokens
use s.new_lexer
use s.parse_tokens

struct syntax_error {
    string message,
    int32 line,
    int32 column,
}

func read_source(string path) Result[string, syntax_error] {
    switch read_to_string(path) {
        Result::Ok(source) : Result::Ok(source),
        Result::Err(err) : Result::Err(syntax_error {
            message: "failed to read source file: " + path + ": " + err.message,
            line: 0,
            column: 0,
        }),
    }
}

func Tokenize(string source) Result[Vec[Token], syntax_error] {
    switch new_lexer(source).tokenize() {
        Result::Ok(tokens) : Result::Ok(tokens),
        Result::Err(err) : Result::Err(syntax_error {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func parse_source(string source) Result[source_file, syntax_error] {
    var tokens = Tokenize(source)?
    parse_tokens(tokens)
}

func parse_tokens(Vec[Token] tokens) Result[source_file, syntax_error] {
    switch parse_tokens(tokens) {
        Result::Ok(ast) : Result::Ok(ast),
        Result::Err(err) : Result::Err(syntax_error {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func dump_tokens_text(Vec[Token] tokens) string {
    dump_tokens(tokens)
}

func dump_source_text(source_file source) string {
    dump_source_file(source)
}
