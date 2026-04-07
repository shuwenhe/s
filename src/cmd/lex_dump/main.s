package cmd

use std.fs.read_to_string
use std.io.eprintln
use std.io.println
use std.prelude.to_string
use std.result.Result
use std.vec.Vec
use s.dump_tokens
use s.new_lexer
use s.Token

struct CliError {
    String message,
}

func main(Vec[String] args) i32 {
    match run(args) {
        Result::Ok(()) => 0,
        Result::Err(err) => {
            eprintln("error: " + err.message)
            1
        }
    }
}

func run(Vec[String] args) Result[(), CliError] {
    var path = parse_path(args)?
    var source = read_source(path)?
    var tokens = lex_source(source)?
    println(dump_tokens(tokens))
    Result::Ok(())
}

func parse_path(Vec[String] args) Result[String, CliError] {
    if len(args) < 2 {
        return Result::Err(CliError {
            message: "usage: lex_dump <path>",
        })
    }
    Result::Ok(args[1])
}

func read_source(String path) Result[String, CliError] {
    match read_to_string(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(_) => Result::Err(CliError {
            message: "failed to read source file: " + path,
        }),
    }
}

func lex_source(String source) Result[Vec[Token], CliError] {
    match new_lexer(source).tokenize() {
        Result::Ok(tokens) => Result::Ok(tokens),
        Result::Err(err) => Result::Err(CliError {
            message: err.message + " at " + to_string(err.line) + ":" + to_string(err.column),
        }),
    }
}
