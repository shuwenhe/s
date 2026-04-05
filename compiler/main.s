package compiler

use std.fs.read_to_string
use std.io.eprintln
use std.io.println
use std.result.Result
use std.vec.Vec
use frontend.dump_source_file
use frontend.dump_tokens
use frontend.new_lexer
use frontend.parse_source

pub struct CliError {
    message: String,
}

pub struct CheckOptions {
    path: String,
    dump_tokens: bool,
    dump_ast: bool,
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
    let command = parse_command(args)?
    let source = read_source(command.path)?

    if command.dump_tokens {
        match new_lexer(source).tokenize() {
            Result::Ok(tokens) => println(dump_tokens(tokens)),
            Result::Err(err) => {
                return Result::Err(CliError {
                    message: "lex error: " + err.message,
                })
            }
        }
    }

    let parsed =
        match parse_source(source) {
            Result::Ok(ast) => ast,
            Result::Err(err) => {
                return Result::Err(CliError {
                    message: "parse error: " + err.message,
                })
            }
        }

    if command.dump_ast {
        println(dump_source_file(parsed))
    }

    println("ok: " + command.path)
    Result::Ok(())
}

pub fn parse_command(args: Vec[String]) -> Result[CheckOptions, CliError] {
    if args.len() < 3 {
        return usage_error()
    }
    if args[1] != "check" {
        return usage_error()
    }

    let options = CheckOptions {
        path: args[2],
        dump_tokens: false,
        dump_ast: false,
    }

    let index = 3
    while index < args.len() {
        let flag = args[index]
        if flag == "--dump-tokens" {
            options.dump_tokens = true
        } else if flag == "--dump-ast" {
            options.dump_ast = true
        } else {
            return Result::Err(CliError {
                message: "unknown flag: " + flag,
            })
        }
        index = index + 1
    }

    Result::Ok(options)
}

pub fn read_source(path: String) -> Result[String, CliError] {
    match read_to_string(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(_) => Result::Err(CliError {
            message: "failed to read source file: " + path,
        }),
    }
}

pub fn usage_error() -> Result[CheckOptions, CliError] {
    Result::Err(CliError {
        message: "usage: s check <path> [--dump-tokens] [--dump-ast]",
    })
}
