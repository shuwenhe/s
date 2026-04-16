package compiler

use compiler.backend_elf64.BackendError
use compiler.backend_elf64.buildExecutable
use std.fs.ReadToString
use std.io.eprintln
use std.io.println
use std.prelude.char_at
use std.prelude.slice
use std.result.Result
use std.vec.Vec
use frontend.dump_source_file
use frontend.dump_tokens
use frontend.new_lexer
use frontend.parse_source

struct checkOptions {
    String command,
    String path,
    String output,
    bool dump_tokens,
    bool dump_ast,
}

func main(Vec[String] args) -> i32 {
    match run(args) {
        Ok(_) => 0,
        Err(err) => {
            eprintln("error: " + err);
            1
        }
    }
}

func run(Vec[String] args) -> Result[int, String] {
    var command =
        match parseCommand(args) {
            Ok(value) => value,
            Err(err) => {
                return Err(err.message)
            }
        }
    var source =
        match readSource(command.path) {
            Ok(value) => value,
            Err(err) => {
                return Err(err.message)
            }
        }
    var parsed =
        match parseCheckedSource(command, source) {
            Ok(value) => value,
            Err(err) => {
                return Err(err.message)
            }
        }

    if command.command == "check" {
        println("ok: " + command.path);
        return Ok(0)
    }
    if command.command == "build" {
        match emitBinary(parsed, command.output) {
            Ok(_) => 0,
            Err(err) => {
                return Err(err)
            }
        }
        println("built: " + command.output);
        return Ok(0)
    }
    return Err("unknown command: " + command.command)
}

func parseCommand(Vec[String] args) -> Result[checkOptions, String] {
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
        return Err("expected -o before output path")
        }
        options.output = normalizeOutputPath(args[4])
        return Ok(options)
    }

    var index = 3
    while index < args.len() {
        var flag = args[index]
        if flag == "--dump-tokens" {
            options.dump_tokens = true
        } else if flag == "--dump-ast" {
            options.dump_ast = true
        } else {
            return Err("unknown flag: " + flag)
        }
        index = index + 1
    }

    return Ok(options)
}

func parseCheckedSource(checkOptions command, String source) -> Result[frontend.SourceFile, String] {
    if command.dump_tokens {
        match new_lexer(source).tokenize() {
            Ok(tokens) => println(dump_tokens(tokens)),
            Err(err) => {
                return Err("lex error: " + err.message)
            }
        }
    }

    var parsed =
        match parse_source(source) {
            Ok(ast) => ast,
            Err(err) => {
                return Err("parse error: " + err.message)
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
        return Err("semantic check failed")
    }

    return Ok(parsed)
}

func emitBinary(frontend.SourceFile parsed, String outputPath) -> Result[int, String] {
    return match buildExecutable(parsed, outputPath) {
        Ok(_) => Ok(0),
        Err(err) => backendError(err),
    }
}

func backendError(BackendError err) -> Result[int, String] {
    return Err(err.message)
}

func readSource(String path) -> Result[String, String] {
    return match ReadToString(path) {
        Ok(source) => Ok(source),
        Err(_) => Err("failed to read source file: " + path),
    }
}

func usageError() -> Result[checkOptions, String] {
    return Err("usage: s check <path> [--dump-tokens] [--dump-ast] | s build <path> -o <output>")
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
