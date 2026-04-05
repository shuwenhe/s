package slatec

use std.fs.read_to_string
use std.io.eprintln
use std.io.println
use std.result.Result
use std.vec.Vec
use slatec.backend_elf64.BackendError
use slatec.backend_elf64.build_executable
use slatec.lexer.LexError
use slatec.lexer.new_lexer
use slatec.parser.ParseError
use slatec.parser.new_parser
use slatec.semantic.SemanticError
use slatec.semantic.check

struct CliError {
    String message,
}

struct BuildOptions {
    String path,
    String output,
}

func main(Vec[String] args) -> i32 {
    match run(args) {
        Result::Ok(()) => 0,
        Result::Err(err) => {
            eprintln("error: " + err.message)
            1
        }
    }
}

func run(Vec[String] args) -> Result[(), CliError] {
    var options = parse_build_options(args)?
    var source_text = read_source(options.path)?
    var tokens = lex_source(source_text)?
    var source = parse_source(tokens)?
    check_source(source)?
    emit_binary(source, options.output)?
    println("built: " + options.output)
    Result::Ok(())
}

func parse_build_options(Vec[String] args) -> Result[BuildOptions, CliError] {
    if args.len() < 4 {
        return Result::Err(CliError {
            message: "usage: slatec build <path> -o <output>",
        })
    }

    Result::Ok(BuildOptions {
        path: args[2],
        output: args[4],
    })
}

func read_source(String path) -> Result[String, CliError] {
    match read_to_string(path) {
        Result::Ok(source_text) => Result::Ok(source_text),
        Result::Err(_) => Result::Err(CliError {
            message: "failed to read source file: " + path,
        }),
    }
}

func lex_source(String source_text) -> Result[Vec[slatec.lexer.Token], CliError] {
    match new_lexer(source_text).tokenize() {
        Result::Ok(tokens) => Result::Ok(tokens),
        Result::Err(err) => lex_error(err),
    }
}

func parse_source(Vec[slatec.lexer.Token] tokens) -> Result[slatec.ast.SourceFile, CliError] {
    match new_parser(tokens).parse() {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(err) => parse_error(err),
    }
}

func check_source(slatec.ast.SourceFile source) -> Result[(), CliError] {
    match check(source) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => semantic_error(err),
    }
}

func emit_binary(slatec.ast.SourceFile source, String output_path) -> Result[(), CliError] {
    match build_executable(source, output_path) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => backend_error(err),
    }
}

func lex_error(LexError err) -> Result[Vec[slatec.lexer.Token], CliError] {
    Result::Err(CliError {
        message: err.message,
    })
}

func parse_error(ParseError err) -> Result[slatec.ast.SourceFile, CliError] {
    Result::Err(CliError {
        message: err.message,
    })
}

func semantic_error(SemanticError err) -> Result[(), CliError] {
    Result::Err(CliError {
        message: err.message,
    })
}

func backend_error(BackendError err) -> Result[(), CliError] {
    Result::Err(CliError {
        message: err.message,
    })
}

