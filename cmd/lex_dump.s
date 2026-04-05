package cmd

use std.fs.read_to_string
use std.io.eprintln
use std.io.println
use std.prelude.to_string
use std.result.Result
use std.vec.Vec
use frontend.dump_tokens
use frontend.new_lexer
use frontend.Token

pub struct CliError {
    message: String,
}

pub fn main(args: Vec[String]) -> i32 {
    match run(args) {
        Result::Ok(()) => 0,
        Result::Err(err) => {
            eprintln("error: " + err.message)
            1
        }
    }
}

pub fn run(args: Vec[String]) -> Result[(), CliError] {
    var path = parse_path(args)?
    var source = read_source(path)?
    var tokens = lex_source(source)?
    println(dump_tokens(tokens))
    Result::Ok(())
}

pub fn parse_path(args: Vec[String]) -> Result[String, CliError] {
    if len(args) < 2 {
        return Result::Err(CliError {
            message: "usage: lex_dump <path>",
        })
    }
    Result::Ok(args[1])
}

pub fn read_source(path: String) -> Result[String, CliError] {
    match read_to_string(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(_) => Result::Err(CliError {
            message: "failed to read source file: " + path,
        }),
    }
}

pub fn lex_source(source: String) -> Result[Vec[Token], CliError] {
    match new_lexer(source).tokenize() {
        Result::Ok(tokens) => Result::Ok(tokens),
        Result::Err(err) => Result::Err(CliError {
            message: err.message + " at " + to_string(err.line) + ":" + to_string(err.column),
        }),
    }
}
