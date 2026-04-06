package compiler.internal.gc

use compiler.backend_elf64.BackendError
use compiler.backend_elf64.buildExecutable
use compiler.internal.base.ParseCommand
use compiler.internal.base.checkOptions
use compiler.internal.base.cliError
use compiler.internal.syntax.DumpAstText
use compiler.internal.syntax.DumpTokensText
use compiler.internal.syntax.ParseSourceText
use compiler.internal.syntax.ReadSource
use compiler.internal.typecheck.CheckSource
use std.fs.MakeTempDir
use std.io.eprintln
use std.io.println
use std.process.RunProcess
use std.result.Result
use std.vec.Vec

func Main(Vec[String] args) -> i32 {
    match Run(args) {
        Result::Ok(()) => 0,
        Result::Err(err) => {
            eprintln("error: " + err.message)
            1
        }
    }
}

func Run(Vec[String] args) -> Result[(), cliError] {
    var command = ParseCommand(args)?
    var source = ReadSource(command.path)?
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

func parseCheckedSource(checkOptions command, String source) -> Result[s.SourceFile, cliError] {
    if command.dump_tokens {
        println(DumpTokensText(source)?)
    }

    var parsed = ParseSourceText(source)?

    if command.dump_ast {
        println(DumpAstText(parsed))
    }

    var checked = CheckSource(parsed)
    if checked.diagnostics.len() > 0 {
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

func tempRunOutputPath() -> Result[String, cliError] {
    match MakeTempDir("s-run-") {
        Result::Ok(path) => Result::Ok(path + "/run-target"),
        Result::Err(err) => Result::Err(cliError {
            message: "failed to create run temp dir: " + err.message,
        }),
    }
}
