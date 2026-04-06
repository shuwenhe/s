package cmd

use std.fs.read_to_string
use std.io.eprintln
use std.io.println
use std.prelude.to_string
use std.result.Result
use std.vec.Vec
use frontend.SourceFile
use frontend.dump_source_file
use frontend.parse_source

struct CliError {
    String message,
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
    var path = parse_path(args)?
    var source = read_source(path)?
    var ast = parse_ast(source)?
    println(dump_source_file(ast))
    Result::Ok(())
}

func parse_path(Vec[String] args) -> Result[String, CliError] {
    if len(args) < 2 {
        return Result::Err(CliError {
            message: "usage: ast_dump <path>",
        })
    }
    Result::Ok(args[1])
}

func read_source(String path) -> Result[String, CliError] {
    match read_to_string(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(_) => Result::Err(CliError {
            message: "failed to read source file: " + path,
        }),
    }
}

func parse_ast(String source) -> Result[SourceFile, CliError] {
    match parse_source(source) {
        Result::Ok(ast) => Result::Ok(ast),
        Result::Err(err) => Result::Err(CliError {
            message: err.message + " at " + to_string(err.line) + ":" + to_string(err.column),
        }),
    }
}
