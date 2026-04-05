package selfhost.cmd

use std.fs.read_to_string
use std.io.eprintln
use std.io.println
use std.prelude.to_string
use std.result.Result
use std.vec.Vec
use selfhost.frontend.SourceFile
use selfhost.frontend.dump_source_file
use selfhost.frontend.parse_source

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
    let path = parse_path(args)?
    let source = read_source(path)?
    let ast = parse_ast(source)?
    println(dump_source_file(ast))
    Result::Ok(())
}

pub fn parse_path(args: Vec[String]) -> Result[String, CliError] {
    if len(args) < 2 {
        return Result::Err(CliError {
            message: "usage: ast_dump <path>",
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

pub fn parse_ast(source: String) -> Result[SourceFile, CliError] {
    match parse_source(source) {
        Result::Ok(ast) => Result::Ok(ast),
        Result::Err(err) => Result::Err(CliError {
            message: err.message + " at " + to_string(err.line) + ":" + to_string(err.column),
        }),
    }
}
