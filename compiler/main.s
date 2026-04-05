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

struct cliError {
    String message,
}

struct checkOptions {
    String path,
    bool dump_tokens,
    bool dump_ast,
}

i32 Main(Vec[String] args) {
    match run(args) {
        Result::Ok(()) => 0,
        Result::Err(err) => {
            eprintln("error: " + err.message)
            1
        }
    }
}

Result[(), cliError] run(Vec[String] args) {
    var command = parseCommand(args)?
    var source = readSource(command.path)?

    if command.dump_tokens {
        match new_lexer(source).tokenize() {
            Result::Ok(tokens) => println(dump_tokens(tokens)),
            Result::Err(err) => {
                return Result::Err(cliError {
                    message: "lex error: " + err.message,
                })
            }
        }
    }

    var parsed =
        match parse_source(source) {
            Result::Ok(ast) => ast,
            Result::Err(err) => {
                return Result::Err(cliError {
                    message: "parse error: " + err.message,
                })
            }
        }

    if command.dump_ast {
        println(dump_source_file(parsed))
    }

    var checked = CheckSource(parsed)
    if !IsOK(checked) {
        for diagnostic in checked.diagnostics {
            eprintln("error: " + diagnostic.message)
        }
        return Result::Err(cliError {
            message: "semantic check failed",
        })
    }

    println("ok: " + command.path)
    Result::Ok(())
}

Result[checkOptions, cliError] parseCommand(Vec[String] args) {
    if args.len() < 3 {
        return usageError()
    }
    if args[1] != "check" {
        return usageError()
    }

    var options = checkOptions {
        path: args[2],
        dump_tokens: false,
        dump_ast: false,
    }

    var index = 3
    while index < args.len() {
        var flag = args[index]
        if flag == "--dump-tokens" {
            options.dump_tokens = true
        } else if flag == "--dump-ast" {
            options.dump_ast = true
        } else {
            return Result::Err(cliError {
                message: "unknown flag: " + flag,
            })
        }
        index = index + 1
    }

    Result::Ok(options)
}

Result[String, cliError] readSource(String path) {
    match read_to_string(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(_) => Result::Err(cliError {
            message: "failed to read source file: " + path,
        }),
    }
}

Result[checkOptions, cliError] usageError() {
    Result::Err(cliError {
        message: "usage: s check <path> [--dump-tokens] [--dump-ast]",
    })
}
