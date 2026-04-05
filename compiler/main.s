package compiler

use compiler.backend_elf64.BackendError
use compiler.backend_elf64.buildExecutable
use std.fs.ReadToString
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
    String command,
    String path,
    String output,
    bool dump_tokens,
    bool dump_ast,
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

func run(Vec[String] args) -> Result[(), cliError] {
    var command = parseCommand(args)?
    var source = readSource(command.path)?
    var parsed = parseCheckedSource(command, source)?

    if command.command == "check" {
        println("ok: " + command.path)
        return Result::Ok(())
    }
    if command.command == "build" {
        emitBinary(parsed, command.output)?
        println("built: " + command.output)
        return Result::Ok(())
    }
    Result::Err(cliError {
        message: "unknown command: " + command.command,
    })
}

func parseCommand(Vec[String] args) -> Result[checkOptions, cliError] {
    if args.len() < 3 {
        return usageError()
    }
    if args[1] != "check" && args[1] != "build" {
        return usageError()
    }

    var options = checkOptions {
        command: args[1],
        path: args[2],
        output: "",
        dump_tokens: false,
        dump_ast: false,
    }

    if options.command == "build" {
        if args.len() < 5 {
            return usageError()
        }
        if args[3] != "-o" {
            return Result::Err(cliError {
                message: "expected -o before output path",
            })
        }
        options.output = args[4]
        return Result::Ok(options)
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

func parseCheckedSource(checkOptions command, String source) -> Result[frontend.SourceFile, cliError] {
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

    Result::Ok(parsed)
}

func emitBinary(frontend.SourceFile parsed, String outputPath) -> Result[(), cliError] {
    match buildExecutable(parsed, outputPath) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => backendError(err),
    }
}

func backendError(BackendError err) -> Result[(), cliError] {
    Result::Err(cliError {
        message: err.message,
    })
}

func readSource(String path) -> Result[String, cliError] {
    match ReadToString(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(_) => Result::Err(cliError {
            message: "failed to read source file: " + path,
        }),
    }
}

func usageError() -> Result[checkOptions, cliError] {
    Result::Err(cliError {
        message: "usage: s check <path> [--dump-tokens] [--dump-ast] | s build <path> -o <output>",
    })
}
