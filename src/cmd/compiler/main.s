package compiler

use compiler.backend_elf64.BackendError
use compiler.backend_elf64.buildExecutable
use std.fs.MakeTempDir
use std.fs.ReadToString
use std.io.eprintln
use std.io.println
use std.prelude.char_at
use std.prelude.slice
use std.process.RunProcess
use std.result.Result
use std.vec.Vec
use s.dump_source_file
use s.dump_tokens
use s.new_lexer
use s.parse_source

struct cliError {
    String message,
}

struct checkOptions {
    String command,
    String path,
    String output,
    bool dump_tokens,
    bool dump_ast,
    Vec[String] run_args,
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
    if command.command == "run" {
        runSource(parsed, command)?
        return Result::Ok(())
    }
    Result::Err(cliError {
        message: "unknown command: " + command.command,
    })
}

func parseCommand(Vec[String] args) -> Result[checkOptions, cliError] {
    if args.len() < 2 {
        return usageError()
    }
    if args[0] != "check" && args[0] != "build" && args[0] != "run" {
        return usageError()
    }

    var options = checkOptions {
        command: args[0],
        path: args[1],
        output: "",
        dump_tokens: false,
        dump_ast: false,
        run_args: Vec[String](),
    }

    if options.command == "build" {
        if args.len() < 4 {
            return usageError()
        }
        if args[2] != "-o" {
            return Result::Err(cliError {
                message: "expected -o before output path",
            })
        }
        options.output = normalizeOutputPath(args[3])
        return Result::Ok(options)
    }

    if options.command == "run" {
        var index = 2
        while index < args.len() {
            options.run_args.push(args[index]);
            index = index + 1
        }
        return Result::Ok(options)
    }

    var index = 2
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

func parseCheckedSource(checkOptions command, String source) -> Result[s.SourceFile, cliError] {
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

func emitBinary(s.SourceFile parsed, String outputPath) -> Result[(), cliError] {
    match buildExecutable(parsed, outputPath) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => backendError(err),
    }
}

func runSource(s.SourceFile parsed, checkOptions command) -> Result[(), cliError] {
    var outputPath = tempRunOutputPath()?
    emitBinary(parsed, outputPath)?

    var argv = Vec[String]()
    argv.push(outputPath);
    for value in command.run_args {
        argv.push(value);
    }

    match RunProcess(argv) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => Result::Err(cliError {
            message: "run failed: " + err.message,
        }),
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
        message:
            "usage: s check <path> [--dump-tokens] [--dump-ast] | " +
            "s build <path> -o <output> | s run <path> [args...]",
    })
}

func tempRunOutputPath() -> Result[String, cliError] {
    match MakeTempDir("s-run-") {
        Result::Ok(path) => Result::Ok(path + "/run-target"),
        Result::Err(err) => Result::Err(cliError {
            message: "failed to create run temp dir: " + err.message,
        }),
    }
}

func normalizeOutputPath(String outputPath) -> String {
    if outputPath.len() > 0 && char_at(outputPath, 0) == "/" {
        return outputPath
    }
    return "/app/tmp/" + lastPathSegment(outputPath)
}

func lastPathSegment(String path) -> String {
    var index = path.len() - 1
    while index >= 0 {
        if char_at(path, index) == "/" {
            return slice(path, index + 1, path.len())
        }
        index = index - 1
    }
    return path
}
