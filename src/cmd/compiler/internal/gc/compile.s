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
use s.ImplDecl
use std.fs.MakeTempDir
use std.io.eprintln
use std.io.println
use std.option.Option
use std.process.RunProcess
use std.result.Result
use std.vec.Vec

struct FrontendResult {
    checkOptions command,
    String source,
    s.SourceFile parsed,
}

struct CompileResult {
    FrontendResult frontend,
    CompileQueue queue,
    Vec[OwnershipEntry] ownership,
    MIRProgram mir,
}

struct FunctionCompileUnit {
    String name,
    FunctionDecl decl,
    String origin,
    bool prepared,
    bool compiled,
}

struct CompileQueue {
    Vec[FunctionCompileUnit] units,
    String entry_name,
}

func RunCommand(Vec[String] args) -> Result[(), cliError] {
    var command = ParseCommand(args)?
    var frontend = FrontendPhase(command)?

    if command.command == "check" {
        println("ok: " + command.path)
        return Result::Ok(())
    }

    var compiled = CompilePhase(frontend)?
    if command.command == "build" {
        emitBinary(compiled, command.output)?
        println("built: " + command.output)
        return Result::Ok(())
    }
    if command.command == "run" {
        runBinary(compiled)?
        return Result::Ok(())
    }
    Result::Err(cliError {
        message: "unknown command: " + command.command,
    })
}

func FrontendPhase(checkOptions command) -> Result[FrontendResult, cliError] {
    var source = LoadSource(command)?
    var parsed = ParsePhase(command, source)?
    TypecheckPhase(parsed)?
    BorrowPhase(parsed)?
    Result::Ok(FrontendResult {
        command: command,
        source: source,
        parsed: parsed,
    })
}

func CompilePhase(FrontendResult frontend) -> Result[CompileResult, cliError] {
    var queue = PrepareCompileQueue(frontend.parsed)
    var ownership = OwnershipPhase(frontend.parsed)
    var result = CompileFunctions(frontend, queue, ownership)?
    Result::Ok(CompileResult {
        frontend: frontend,
        queue: result.queue,
        ownership: ownership,
        mir: result.mir,
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

func PrepareFunc(FunctionDecl func, String origin) -> Option[FunctionCompileUnit] {
    if func.sig.name == "_" {
        return Option::None
    }
    match func.body {
        Option::Some(_) => {
            return Option::Some(FunctionCompileUnit {
                name: func.sig.name,
                decl: func,
                origin: origin,
                prepared: true,
                compiled: false,
            })
        }
        Option::None => Option::None,
    }
}

func EnqueueFunc(Vec[FunctionCompileUnit] queue, FunctionDecl func, String origin) -> () {
    match PrepareFunc(func, origin) {
        Option::Some(unit) => queue.push(unit),
        Option::None => (),
    }
}

func PrepareCompileQueue(s.SourceFile parsed) -> CompileQueue {
    var units = Vec[FunctionCompileUnit]()
    var entry_name = ""

    for item in parsed.items {
        match item {
            s.Item::Function(func) => {
                EnqueueFunc(units, func, parsed.package)
                if func.sig.name == "main" {
                    entry_name = "main"
                }
            }
            s.Item::Impl(impl_decl) => {
                enqueueImplMethods(units, impl_decl, parsed.package)
            }
            _ => (),
        }
    }

    CompileQueue {
        units: units,
        entry_name: entry_name,
    }
}

func LowerToIR(
    FrontendResult frontend,
    FunctionCompileUnit unit,
    Vec[OwnershipEntry] ownership,
    bool is_entry
) -> Result[MIRProgram, cliError] {
    match LowerFunction(frontend.parsed, unit.decl, ownership, is_entry) {
        Result::Ok(mir) => Result::Ok(mir),
        Result::Err(err) => Result::Err(cliError {
            message: "ir lowering failed: " + err,
        }),
    }
}

func CompileFunctions(
    FrontendResult frontend,
    CompileQueue queue,
    Vec[OwnershipEntry] ownership
) -> Result[CompileResult, cliError] {
    var programs = Vec[MIRProgram]()
    for unit in queue.units {
        programs.push(LowerToIR(frontend, unit, ownership, unit.name == queue.entry_name)?)
    }
    var mir = MergeMIRPrograms(programs, queue.entry_name)?
    markQueueCompiled(queue)
    Result::Ok(CompileResult {
        frontend: frontend,
        queue: queue,
        ownership: ownership,
        mir: mir,
    })
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

func emitBinary(CompileResult compiled, String outputPath) -> Result[(), cliError] {
    var program = CodegenPhase(compiled.mir)
    LinkPhase(program, outputPath)
}

func runBinary(CompileResult compiled) -> Result[(), cliError] {
    var outputPath = tempRunOutputPath()?
    emitBinary(compiled, outputPath)?

    var argv = Vec[String]()
    argv.push(outputPath);
    for value in compiled.frontend.command.run_args {
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

func enqueueImplMethods(Vec[FunctionCompileUnit] units, ImplDecl impl_decl, String packageName) -> () {
    for method in impl_decl.methods {
        EnqueueFunc(units, method, packageName + ".impl." + impl_decl.target)
    }
}

func markQueueCompiled(CompileQueue queue) -> () {
    var index = 0
    while index < queue.units.len() {
        var unit = queue.units[index]
        queue.units[index] = FunctionCompileUnit {
            name: unit.name,
            decl: unit.decl,
            origin: unit.origin,
            prepared: unit.prepared,
            compiled: true,
        }
        index = index + 1
    }
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
