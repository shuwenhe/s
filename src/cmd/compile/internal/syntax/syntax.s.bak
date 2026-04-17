package compile.internal.syntax

use std.fs.ReadToString
use std.result.Result
use std.vec.Vec
use s.SourceFile
use s.Token
use s.dumpSourceFile
use s.dumpTokens
use s.newLexer
use s.parseTokens

struct SyntaxError {
    string message,
    int32 line,
    int32 column,
}

func ReadSource(string path) Result[string, SyntaxError] {
    match ReadToString(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(err) => Result::Err(SyntaxError {
            message: "failed to read source file: " + path + ": " + err.message,
            line: 0,
            column: 0,
        }),
    }
}

func Tokenize(string source) Result[Vec[Token], SyntaxError] {
    match newLexer(source).tokenize() {
        Result::Ok(tokens) => Result::Ok(tokens),
        Result::Err(err) => Result::Err(SyntaxError {
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
    match parseTokens(tokens) {
        Result::Ok(ast) => Result::Ok(ast),
        Result::Err(err) => Result::Err(SyntaxError {
            message: err.message,
            line: err.line,
            column: err.column,
        }),
    }
}

func DumpTokensText(Vec[Token] tokens) string {
    dumpTokens(tokens)
}

func DumpSourceText(SourceFile source) string {
    dumpSourceFile(source)
}
