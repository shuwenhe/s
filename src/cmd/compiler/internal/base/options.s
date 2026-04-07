package compiler.internal.base

use std.prelude.char_at
use std.prelude.slice
use std.result.Result
use std.vec.Vec

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

func ParseCommand(Vec[String] args) Result[checkOptions, cliError] {
    if args.len() < 2 {
        return UsageError()
    }
    if args[0] != "check" && args[0] != "build" && args[0] != "run" {
        return UsageError()
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
            return UsageError()
        }
        if args[2] != "-o" {
            return Result::Err(cliError {
                message: "expected -o before output path",
            })
        }
        options.output = NormalizeOutputPath(args[3])
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

func UsageError() Result[checkOptions, cliError] {
    Result::Err(cliError {
        message:
            "usage: s check <path> [--dump-tokens] [--dump-ast] | " +
            "s build <path> -o <output> | s run <path> [args...]",
    })
}

func NormalizeOutputPath(String outputPath) String {
    if outputPath.len() > 0 && char_at(outputPath, 0) == "/" {
        return outputPath
    }
    return "/app/tmp/" + LastPathSegment(outputPath)
}

func LastPathSegment(String path) String {
    var index = path.len() - 1
    while index >= 0 {
        if char_at(path, index) == "/" {
            return slice(path, index + 1, path.len())
        }
        index = index - 1
    }
    return path
}
