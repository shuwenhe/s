package compile.internal.syntax

use std.fs.ReadToString
use std.result.Result
use std.vec.Vec
use s.SourceFile
use s.Token
use s.dump_source_file
use s.dump_tokens
use s.new_lexer
use s.parse_tokens

struct SyntaxError {
    string message,
    int32 line,
    int32 column,
}

func ReadSource(string path) Result[string, SyntaxError] {
    switch ReadToString(path) {
        Result::Ok(source) : Result::Ok(source),
        Result::Err(err) : Result::Err(SyntaxError {
            message: "failed to read source file: " + path + ": " + err.message,
            line: 0,
            column: 0,
        }),
    }
}

func Tokenize(string source) Result[Vec[Token], SyntaxError] {
    switch new_lexer(source).tokenize() {
        Result::Ok(tokens) : Result::Ok(tokens),
        Result::Err(err) : Result::Err(SyntaxError {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func ParseSource(string source) Result[SourceFile, SyntaxError] {
    var tokens = Tokenize(source)?
    ParseTokens(tokens)
}

func ParseTokens(Vec[Token] tokens) Result[SourceFile, SyntaxError] {
    switch parse_tokens(tokens) {
        Result::Ok(ast) : Result::Ok(ast),
        Result::Err(err) : Result::Err(SyntaxError {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func DumpTokensText(Vec[Token] tokens) string {
    dump_tokens(tokens)
}

func DumpSourceText(SourceFile source) string {
    dump_source_file(source)
}
