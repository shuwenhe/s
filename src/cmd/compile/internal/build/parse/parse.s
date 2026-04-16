package compile.internal.build.parse

use std.result.Result
use std.vec.Vec

struct CompileOptions {
    String command,
    String path,
    String output,
}

struct ParseError {
    String message,
}

func ParseOptions(Vec[String] args) -> Result[CompileOptions, ParseError] {
    if args.len() < 2 {
        return Result::Ok(CompileOptions {
            command: "help",
            path: "",
            output: "",
        })
    }

    var command = args[1]
    if command == "help" || command == "--help" || command == "-h" {
        return Result::Ok(CompileOptions {
            command: "help",
            path: "",
            output: "",
        })
    }

    if command == "check" || command == "tokens" || command == "ast" {
        if args.len() < 3 {
            return Result::Err(ParseError {
                message: "usage: compile " + command + " <path>",
            })
        }
        return Result::Ok(CompileOptions {
            command: command,
            path: args[2],
            output: "",
        })
    }

    if command == "build" {
        if args.len() < 5 {
            return Result::Err(ParseError {
                message: "usage: compile build <path> -o <output>",
            })
        }
        if args[3] != "-o" {
            return Result::Err(ParseError {
                message: "expected -o before output path",
            })
        }
        return Result::Ok(CompileOptions {
            command: command,
            path: args[2],
            output: args[4],
        })
    }

    if command == "run" {
        if args.len() < 3 {
            return Result::Err(ParseError {
                message: "usage: compile run <path>",
            })
        }
        return Result::Ok(CompileOptions {
            command: command,
            path: args[2],
            output: "",
        })
    }

    Result::Err(ParseError {
        message: "unknown command: " + command,
    })
}

func Usage() -> String {
    "usage:\n"
        + "  compile check <path>\n"
        + "  compile tokens <path>\n"
        + "  compile ast <path>\n"
        + "  compile build <path> -o <output>\n"
        + "  compile run <path>\n"
}
