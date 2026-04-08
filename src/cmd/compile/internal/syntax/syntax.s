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
    String message,
    int32 line,
    int32 column,
}

func ReadSource(String path) Result[String, SyntaxError] {
    match ReadToString(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(err) => Result::Err(SyntaxError {
            message: "failed to read source file: " + path + ": " + err.message,
            line: 0,
            column: 0,
        }),
    }
}

func Tokenize(String source) Result[Vec[Token], SyntaxError] {
    match new_lexer(source).tokenize() {
        Result::Ok(tokens) => Result::Ok(tokens),
        Result::Err(err) => Result::Err(SyntaxError {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func ParseSource(String source) Result[SourceFile, SyntaxError] {
    var tokens = Tokenize(source)?
    ParseTokens(tokens)
}

func ParseTokens(Vec[Token] tokens) Result[SourceFile, SyntaxError] {
    match parse_tokens(tokens) {
        Result::Ok(ast) => Result::Ok(ast),
        Result::Err(err) => Result::Err(SyntaxError {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func DumpTokensText(Vec[Token] tokens) String {
    dump_tokens(tokens)
}

func DumpSourceText(SourceFile source) String {
    dump_source_file(source)
}
