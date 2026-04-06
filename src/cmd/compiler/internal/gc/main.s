package compiler.internal.gc

use compiler.backend_elf64.BackendError
use compiler.internal.amd64.ArchName
use compiler.internal.amd64.LinkProgram
use compiler.internal.base.ParseCommand
use compiler.internal.base.checkOptions
use compiler.internal.base.cliError
use compiler.internal.ir.LowerSource
use compiler.internal.ir.MIRProgram
use compiler.internal.ssagen.LowerProgram
use compiler.internal.ssagen.MachineProgram
use compiler.internal.syntax.DumpAstText
use compiler.internal.syntax.DumpTokensText
use compiler.internal.syntax.ParseSourceText
use compiler.internal.syntax.ReadSource
use compiler.internal.typecheck.AnalyzeBlock
use compiler.internal.typecheck.CheckSource
use compiler.internal.typecheck.MakePlan
use compiler.internal.typecheck.OwnershipEntry
use compiler.internal.typecheck.ParseType
use compiler.internal.typecheck.TypeBinding
use compiler.internal.typecheck.VarState
use s.FunctionDecl
use std.fs.MakeTempDir
use std.io.eprintln
use std.io.println
use std.option.Option
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
    var source = LoadSource(command)?
    var parsed = ParsePhase(command, source)?
    TypecheckPhase(parsed)?
    BorrowPhase(parsed)?
    var ownership = OwnershipPhase(parsed)
    var mir = LowerToIR(parsed, ownership)?

    if command.command == "check" {
        println("ok: " + command.path)
        return Result::Ok(())
    }
    if command.command == "build" {
        emitBinary(mir, command.output)?
        println("built: " + command.output)
        return Result::Ok(())
    }
    if command.command == "run" {
        runSource(mir, command)?
        return Result::Ok(())
    }
    Result::Err(cliError {
        message: "unknown command: " + command.command,
    })
}

func LoadSource(checkOptions command) -> Result[String, cliError] {
    ReadSource(command.path)
}

func ParsePhase(checkOptions command, String source) -> Result[s.SourceFile, cliError] {
    if command.dump_tokens {
        println(DumpTokensText(source)?)
    }

    var parsed = ParseSourceText(source)?

    if command.dump_ast {
        println(DumpAstText(parsed))
    }

    Result::Ok(parsed)
}

func TypecheckPhase(s.SourceFile parsed) -> Result[(), cliError] {
    var checked = CheckSource(parsed)
    if checked.diagnostics.len() > 0 {
        for diagnostic in checked.diagnostics {
            eprintln("error: " + diagnostic.message)
        }
        return Result::Err(cliError {
            message: "semantic check failed",
        })
    }
    Result::Ok(())
}

func BorrowPhase(s.SourceFile parsed) -> Result[(), cliError] {
    for item in parsed.items {
        match item {
            s.Item::Function(func) => {
                match func.body {
                    Option::Some(body) => {
                        var scope = initialScope(func)
                        var diagnostics = AnalyzeBlock(body, scope)
                        for diagnostic in diagnostics {
                            eprintln("error: " + diagnostic.message)
                        }
                        if diagnostics.len() > 0 {
                            return Result::Err(cliError {
                                message: "borrow check failed",
                            })
                        }
                    }
                    Option::None => (),
                }
            }
            _ => (),
        }
    }
    Result::Ok(())
}

func OwnershipPhase(s.SourceFile parsed) -> Vec[OwnershipEntry] {
    MakePlan(collectTypeBindings(parsed))
}

func LowerToIR(s.SourceFile parsed, Vec[OwnershipEntry] ownership) -> Result[MIRProgram, cliError] {
    match LowerSource(parsed, ownership) {
        Result::Ok(mir) => Result::Ok(mir),
        Result::Err(err) => Result::Err(cliError {
            message: "ir lowering failed: " + err,
        }),
    }
}

func CodegenPhase(MIRProgram mir) -> MachineProgram {
    LowerProgram(mir, ArchName())
}

func LinkPhase(MachineProgram program, String outputPath) -> Result[(), cliError] {
    match LinkProgram(program, outputPath) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => backendError(err),
    }
}

func emitBinary(MIRProgram mir, String outputPath) -> Result[(), cliError] {
    var program = CodegenPhase(mir)
    LinkPhase(program, outputPath)
}

func runSource(MIRProgram mir, checkOptions command) -> Result[(), cliError] {
    var outputPath = tempRunOutputPath()?
    emitBinary(mir, outputPath)?

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

func collectTypeBindings(s.SourceFile parsed) -> Vec[TypeBinding] {
    var bindings = Vec[TypeBinding]()
    for item in parsed.items {
        match item {
            s.Item::Function(func) => {
                for param in func.sig.params {
                    bindings.push(TypeBinding {
                        name: param.name,
                        value: ParseType(param.type_name),
                    })
                }
            }
            _ => (),
        }
    }
    bindings
}

func initialScope(FunctionDecl func) -> Vec[VarState] {
    var scope = Vec[VarState]()
    for param in func.sig.params {
        scope.push(VarState {
            name: param.name,
            ty: ParseType(param.type_name),
        })
    }
    scope
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
