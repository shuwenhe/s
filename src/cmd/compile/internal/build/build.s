package compile.internal.build

use compile.internal.backend.Build as BuildBinary
use compile.internal.backend.CliError as BackendCliError
use compile.internal.backend.Run as RunBinary
use compile.internal.check.CheckFrontend
use compile.internal.check.CliError as CheckCliError
use compile.internal.check.LoadFrontend
use compile.internal.syntax.DumpSourceText
use compile.internal.syntax.DumpTokensText
use std.io.eprintln
use std.io.println
use std.result.Result
use std.vec.Vec

struct CompileOptions {
    String command,
    String path,
    String output,
}

struct CliError {
    String message,
}

func Main(Vec[String] args) i32 {
    match Run(args) {
        Result::Ok(()) => 0,
        Result::Err(err) => {
            eprintln("error: " + err.message)
            1
        }
    }
}

func Run(Vec[String] args) Result[(), CliError] {
    var options = parse_options(args)?

    if options.command == "help" {
        println(usage())
        return Result::Ok(())
    }

    var frontend =
        match LoadFrontend(options.path) {
            Result::Ok(value) => value,
            Result::Err(err) => {
                return Result::Err(convert_check_error(err))
            }
        }

    match CheckFrontend(frontend) {
        Result::Ok(()) => (),
        Result::Err(err) => {
            return Result::Err(convert_check_error(err))
        }
    }

    if options.command == "check" {
        println("ok: " + options.path)
        return Result::Ok(())
    }

    if options.command == "tokens" {
        println(DumpTokensText(frontend.tokens))
        return Result::Ok(())
    }

    if options.command == "ast" {
        println(DumpSourceText(frontend.ast))
        return Result::Ok(())
    }

    if options.command == "build" {
        match BuildBinary(options.path, options.output) {
            Result::Ok(()) => (),
            Result::Err(err) => {
                return Result::Err(convert_backend_error(err))
            }
        }
        return Result::Ok(())
    }

    if options.command == "run" {
        match RunBinary(options.path) {
            Result::Ok(()) => (),
            Result::Err(err) => {
                return Result::Err(convert_backend_error(err))
            }
        }
        return Result::Ok(())
    }

    Result::Err(CliError {
        message: "unknown command: " + options.command,
    })
}

func parse_options(Vec[String] args) Result[CompileOptions, CliError] {
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
            return Result::Err(CliError {
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
            return Result::Err(CliError {
                message: "usage: compile build <path> -o <output>",
            })
        }
        if args[3] != "-o" {
            return Result::Err(CliError {
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
            return Result::Err(CliError {
                message: "usage: compile run <path>",
            })
        }
        return Result::Ok(CompileOptions {
            command: command,
            path: args[2],
            output: "",
        })
    }

    Result::Err(CliError {
        message: "unknown command: " + command,
    })
}

func usage() String {
    "usage:\n"
        + "  compile check <path>\n"
        + "  compile tokens <path>\n"
        + "  compile ast <path>\n"
        + "  compile build <path> -o <output>\n"
        + "  compile run <path>\n"
}

func convert_check_error(CheckCliError err) CliError {
    CliError {
        message: err.message,
    }
}

func convert_backend_error(BackendCliError err) CliError {
    CliError {
        message: err.message,
    }
}
