package compile.internal.check

use compile.internal.syntax.ParseTokens
use compile.internal.syntax.ReadSource
use compile.internal.syntax.SyntaxError
use compile.internal.syntax.Tokenize
use std.prelude.to_string
use std.result.Result
use std.vec.Vec
use s.SourceFile
use s.Token

struct CliError {
    String message,
}

struct FrontendResult {
    String source,
    Vec[Token] tokens,
    SourceFile ast,
}

func LoadFrontend(String path) Result[FrontendResult, CliError] {
    var source = read_source(path)?
    var tokens = tokenize_source(source)?
    var ast = parse_tokens_text(tokens)?
    Result::Ok(FrontendResult {
        source: source,
        tokens: tokens,
        ast: ast,
    })
}

func CheckFrontend(FrontendResult frontend) Result[(), CliError] {
    if frontend.ast.package == "" {
        return Result::Err(CliError {
            message: "missing package declaration",
        })
    }
    Result::Ok(())
}

func read_source(String path) Result[String, CliError] {
    match ReadSource(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(err) => Result::Err(convert_syntax_error(err)),
    }
}

func tokenize_source(String source) Result[Vec[Token], CliError] {
    match Tokenize(source) {
        Result::Ok(tokens) => Result::Ok(tokens),
        Result::Err(err) => Result::Err(convert_syntax_error(err)),
    }
}

func parse_tokens_text(Vec[Token] tokens) Result[SourceFile, CliError] {
    match ParseTokens(tokens) {
        Result::Ok(ast) => Result::Ok(ast),
        Result::Err(err) => Result::Err(convert_syntax_error(err)),
    }
}

func convert_syntax_error(SyntaxError err) CliError {
    if err.line == 0 {
        return CliError {
            message: err.message,
        }
    }
    CliError {
        message: err.message + " at " + to_string(err.line) + ":" + to_string(err.column),
    }
}
