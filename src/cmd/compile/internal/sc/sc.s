package compile.internal.sc

use compile.internal.syntax.DumpSourceText
use compile.internal.syntax.DumpTokensText
use compile.internal.syntax.ParseTokens
use compile.internal.syntax.ReadSource
use compile.internal.syntax.SyntaxError
use compile.internal.syntax.Tokenize
use std.fs.MakeTempDir
use std.io.eprintln
use std.io.println
use std.prelude.to_string
use std.process.RunProcess
use std.result.Result
use std.vec.Vec
use s.SourceFile
use s.Token

struct CliError {
    String message,
}

struct CompileOptions {
    String command,
    String path,
    String output,
}

struct FrontendResult {
    String source,
    Vec[Token] tokens,
    SourceFile ast,
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

    var frontend = load_frontend(options.path)?
    check_frontend(frontend)?

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
        build_with_native_runner(options.path, options.output)?
        return Result::Ok(())
    }

    if options.command == "run" {
        run_with_native_runner(options.path)?
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

func load_frontend(String path) Result[FrontendResult, CliError] {
    var source = read_source(path)?
    var tokens = tokenize_source(source)?
    var ast = parse_tokens_text(tokens)?
    Result::Ok(FrontendResult {
        source: source,
        tokens: tokens,
        ast: ast,
    })
}

func read_source(String path) Result[String, CliError] {
    match ReadSource(path) {
        Result::Ok(source) => Result::Ok(source),
        Result::Err(err) => Result::Err(convert_syntax_error(err)),
    }
}

func tokenize_source(String source) Result[Vec[Token], CliError] {
    match Tokenize(source) {
        Result::Ok(tokens) => Result::Ok(tokens),
        Result::Err(err) => Result::Err(convert_syntax_error(err)),
    }
}

func parse_tokens_text(Vec[Token] tokens) Result[SourceFile, CliError] {
    match ParseTokens(tokens) {
        Result::Ok(ast) => Result::Ok(ast),
        Result::Err(err) => Result::Err(convert_syntax_error(err)),
    }
}

func convert_syntax_error(SyntaxError err) CliError {
    if err.line == 0 {
        return CliError {
            message: err.message,
        }
    }
    CliError {
        message: err.message + " at " + to_string(err.line) + ":" + to_string(err.column),
    }
}

func check_frontend(FrontendResult frontend) Result[(), CliError] {
    if frontend.ast.package == "" {
        return Result::Err(CliError {
            message: "missing package declaration",
        })
    }
    Result::Ok(())
}

func build_with_native_runner(String path, String output) Result[(), CliError] {
    // The frontend now lives in internal/syntax; native runner remains the backend bridge.
    var argv = Vec[String]()
    argv.push("/app/s/bin/s-native")
    argv.push("build")
    argv.push(path)
    argv.push("-o")
    argv.push(output)

    match RunProcess(argv) {
        Result::Ok(()) => {
            println("built: " + output)
            Result::Ok(())
        }
        Result::Err(err) => Result::Err(CliError {
            message: "backend build failed: " + err.message,
        }),
    }
}

func run_with_native_runner(String path) Result[(), CliError] {
    var temp_dir =
        match MakeTempDir("s-compile-") {
            Result::Ok(dir) => dir,
            Result::Err(err) => {
                return Result::Err(CliError {
                    message: "failed to create temp dir: " + err.message,
                })
            }
        }
    var output = temp_dir + "/a.out"
    build_with_native_runner(path, output)?

    var argv = Vec[String]()
    argv.push(output)

    match RunProcess(argv) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => Result::Err(CliError {
            message: "failed to run compiled program: " + err.message,
        }),
    }
}
