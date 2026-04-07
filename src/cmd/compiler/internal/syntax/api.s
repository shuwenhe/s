package compiler.internal.syntax

use compiler.internal.base.cliError
use std.fs.ReadToString
use std.result.Result
use std.vec.Vec
use s.ParseError
use s.SourceFile
use s.Token
use s.dump_source_file
use s.dump_tokens
use s.new_lexer
use s.parse_source

func ReadSource(String path) Result[String, cliError] {
    match ReadToString(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(_) => Result::Err(cliError {
            message: "failed to read source file: " + path,
        }),
    }
}

func LexSource(String source) Result[Vec[Token], cliError] {
    match new_lexer(source).tokenize() {
        Result::Ok(tokens) => Result::Ok(tokens),
        Result::Err(err) => Result::Err(cliError {
            message: "lex error: " + err.message,
        }),
    }
}

func ParseSourceText(String source) Result[SourceFile, cliError] {
    match parse_source(source) {
        Result::Ok(ast) => Result::Ok(ast),
        Result::Err(err) => parseError(err),
    }
}

func DumpTokensText(String source) Result[String, cliError] {
    match LexSource(source) {
        Result::Ok(tokens) => Result::Ok(dump_tokens(tokens)),
        Result::Err(err) => Result::Err(err),
    }
}

func DumpAstText(SourceFile source) String {
    dump_source_file(source)
}

func parseError(ParseError err) Result[SourceFile, cliError] {
    Result::Err(cliError {
        message: "parse error: " + err.message,
    })
}
