package compiler.backend_elf64

use frontend.BlockExpr
use frontend.CallExpr
use frontend.CForStmt
use frontend.Expr
use frontend.ExprStmt
use frontend.FunctionDecl
use frontend.IntExpr
use frontend.Item
use frontend.AssignStmt
use frontend.IncrementStmt
use frontend.NameExpr
use frontend.ReturnStmt
use frontend.SourceFile
use frontend.Stmt
use frontend.StringExpr
use frontend.VarStmt
use std.option.Option
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.result.Result
use std.vec.Vec

struct Program {
    ops: Vec[ProgramOp],
    exitCode: int,
}

struct WriteOp {
    fd: int,
    text: String,
}

struct ExitOp {
    code: int,
}

enum ProgramOp {
    WriteStdout(WriteOp),
    WriteStderr(WriteOp),
    Exit(ExitOp),
}

enum Value {
    Int(int),
    String(String),
    Bool(bool),
    Unit(()),
}

struct LocalBinding {
    name: String,
    value: Value,
}

struct BackendError {
    message: String,
}

struct HostError {
    message: String,
}

func buildExecutable(SourceFile source, String outputPath) -> Result[(), BackendError] {
    // Minimal backend design:
    // 1. compile SourceFile -> linear ProgramOp list
    // 2. emit Linux x86_64 assembly text
    // 3. invoke host as/ld through runtime boundary
    //
    // See /app/s/docs/backend_elf64.md for the executable MVP plan.
    //
    // The runnable algorithm still lives in backend_elf64.py today.
    var program = compileProgram(source)?
    var asmText = emitAsm(program)
    assembleAndLink(asmText, outputPath)
}

func compileProgram(SourceFile source) -> Result[Program, BackendError] {
    var mainFunc = findMain(source)?
    var env = Vec[LocalBinding]()
    var ops = Vec[ProgramOp]()
    var exitCode = executeFunction(mainFunc, env, ops)?
    ops.push(ProgramOp::Exit(ExitOp {
        code: exitCode,
    }))
    Result::Ok(Program {
        ops: ops,
        exitCode: exitCode,
    })
}

func emitAsm(Program program) -> String {
    emitDataSection(program.ops) + "\n" + emitTextSection(program.ops, program.exitCode) + "\n"
}

func findMain(SourceFile source) -> Result[FunctionDecl, BackendError] {
    for item in source.items {
        match item {
            Item::Function(func) => {
                if func.sig.name == "main" {
                    return Result::Ok(func)
                }
            }
            _ => (),
        }
    }
    Result::Err(BackendError {
        message: "entry function main not found",
    })
}

func executeFunction(
    FunctionDecl func,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[int, BackendError] {
    match func.body {
        Option::Some(body) => executeBlock(body, env, ops),
        Option::None => Result::Ok(0),
    }
}

func executeBlock(
    BlockExpr body,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[int, BackendError] {
    for stmt in body.statements {
        match stmt {
            Stmt::Return(value) => return executeReturnStmt(value, env),
            _ => executeStmt(stmt, env, ops)?,
        }
    }
    match body.final_expr {
        Option::Some(expr) => asExitCode(evalExpr(expr, env)?),
        Option::None => Result::Ok(0),
    }
}

func executeStmt(
    Stmt stmt,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[(), BackendError] {
    match stmt {
        Stmt::Var(value) => executeVarStmt(value, env),
        Stmt::Assign(value) => executeAssignStmt(value, env),
        Stmt::Increment(value) => executeIncrementStmt(value, env),
        Stmt::CFor(value) => executeCForStmt(value, env, ops),
        Stmt::Expr(value) => executeExprStmt(value, env, ops),
        Stmt::Return(value) => {
            value
            Result::Ok(())
        }
    }
}

func evalExpr(
    Expr expr,
    Vec[LocalBinding] env,
) -> Result[Value, BackendError] {
    match expr {
        Expr::Int(value) => Result::Ok(Value::Int(parseIntLiteral(value))),
        Expr::String(value) => Result::Ok(Value::String(unquoteString(value))),
        Expr::Bool(value) => Result::Ok(Value::Bool(value.value)),
        Expr::Name(value) => lookupBinding(env, value.name),
        Expr::Binary(value) => evalBinaryExpr(value, env),
        _ => Result::Err(unsupported("backend expr")),
    }
}

func emitDataSection(Vec[ProgramOp] ops) -> String {
    var lines = Vec[String]()
    lines.push(".section .data")
    var index = 0
    for op in ops {
        match op {
            ProgramOp::WriteStdout(write) => appendDataPayload(lines, "message_" + to_string(index), write.text),
            ProgramOp::WriteStderr(write) => appendDataPayload(lines, "message_" + to_string(index), write.text),
            ProgramOp::Exit(_) => (),
        }
        index = index + 1
    }
    joinLines(lines)
}

func emitTextSection(Vec[ProgramOp] ops, int exitCode) -> String {
    var lines = Vec[String]()
    lines.push(".section .text")
    lines.push(".global _start")
    lines.push("_start:")
    var index = 0
    for op in ops {
        match op {
            ProgramOp::WriteStdout(write) => appendWriteSyscall(lines, 1, "message_" + to_string(index), write.text),
            ProgramOp::WriteStderr(write) => appendWriteSyscall(lines, 2, "message_" + to_string(index), write.text),
            ProgramOp::Exit(_) => (),
        }
        index = index + 1
    }
    lines.push("    mov $60, %rax")
    lines.push("    mov $" + to_string(exitCode) + ", %rdi")
    lines.push("    syscall")
    joinLines(lines)
}

func assembleAndLink(String asmText, String outputPath) -> Result[(), BackendError] {
    var tempDir = hostMakeTempDir("s-build-")?
    var asmPath = tempDir + "/out.s"
    var objPath = tempDir + "/out.o"
    hostWriteTextFile(asmPath, asmText)?
    hostRunProcess(Vec[String] { "as", "-o", objPath, asmPath })?
    hostRunProcess(Vec[String] { "ld", "-o", outputPath, objPath })?
    Result::Ok(())
}

func appendDataPayload(Vec[String] lines, String label, String text) -> () {
    lines.push(label + ":")
    lines.push("    .byte " + encodeBytes(text))
}

func appendWriteSyscall(Vec[String] lines, int fd, String label, String text) -> () {
    lines.push("    mov $1, %rax")
    lines.push("    mov $" + to_string(fd) + ", %rdi")
    lines.push("    lea " + label + "(%rip), %rsi")
    lines.push("    mov $" + byteLen(text) + ", %rdx")
    lines.push("    syscall")
}

func encodeBytes(String text) -> String {
    var parts = Vec[String]()
    var index = 0
    while index < len(text) {
        parts.push(to_string(asciiCode(char_at(text, index))))
        index = index + 1
    }
    joinWith(parts, ", ")
}

func byteLen(String text) -> String {
    // MVP: assume ASCII payloads first.
    to_string(text.len())
}

func joinLines(Vec[String] lines) -> String {
    joinWith(lines, "\n")
}

func joinWith(Vec[String] values, String sep) -> String {
    var text = ""
    var index = 0
    while index < values.len() {
        if index > 0 {
            text = text + sep
        }
        text = text + values[index]
        index = index + 1
    }
    text
}

func unsupported(String feature) -> BackendError {
    BackendError {
        message: "unsupported " + feature,
    }
}

func executeVarStmt(
    VarStmt stmt,
    Vec[LocalBinding] env,
) -> Result[(), BackendError] {
    var value = evalExpr(stmt.value, env)?
    setLocal(env, stmt.name, value)
    Result::Ok(())
}

func executeAssignStmt(
    AssignStmt stmt,
    Vec[LocalBinding] env,
) -> Result[(), BackendError] {
    var value = evalExpr(stmt.value, env)?
    if !hasLocal(env, stmt.name) {
        return Result::Err(BackendError {
            message: "undefined name " + stmt.name,
        })
    }
    setLocal(env, stmt.name, value)
    Result::Ok(())
}

func executeIncrementStmt(
    IncrementStmt stmt,
    Vec[LocalBinding] env,
) -> Result[(), BackendError] {
    var current = lookupBinding(env, stmt.name)?
    match current {
        Value::Int(number) => {
            setLocal(env, stmt.name, Value::Int(number + 1))
            Result::Ok(())
        }
        _ => Result::Err(unsupported("increment target")),
    }
}

func executeCForStmt(
    CForStmt stmt,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[(), BackendError] {
    executeStmt(stmt.init.value, env, ops)?
    while isTrue(evalExpr(stmt.condition, env)?) {
        executeBlock(stmt.body, env, ops)?
        executeStmt(stmt.step.value, env, ops)?
    }
    Result::Ok(())
}

func executeExprStmt(
    ExprStmt stmt,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[(), BackendError] {
    match stmt.expr {
        Expr::Call(value) => executeCallStmt(value, env, ops),
        _ => {
            evalExpr(stmt.expr, env)?
            Result::Ok(())
        }
    }
}

func executeCallStmt(
    CallExpr call,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[(), BackendError] {
    var calleeName = extractCalleeName(call)?
    if len(call.args) != 1 {
        return Result::Err(unsupported("call arity"))
    }
    var value = evalExpr(call.args[0], env)?
    var text = valueToString(value)?

    if calleeName == "println" {
        ops.push(ProgramOp::WriteStdout(WriteOp {
            fd: 1,
            text: text + "\n",
        }))
        return Result::Ok(())
    }
    if calleeName == "eprintln" {
        ops.push(ProgramOp::WriteStderr(WriteOp {
            fd: 2,
            text: text + "\n",
        }))
        return Result::Ok(())
    }
    Result::Err(unsupported("call " + calleeName))
}

func executeReturnStmt(
    ReturnStmt stmt,
    Vec[LocalBinding] env,
) -> Result[int, BackendError] {
    match stmt.value {
        Option::Some(expr) => asExitCode(evalExpr(expr, env)?),
        Option::None => Result::Ok(0),
    }
}

func evalBinaryExpr(
    frontend.BinaryExpr expr,
    Vec[LocalBinding] env,
) -> Result[Value, BackendError] {
    var left = evalExpr(expr.left.value, env)?
    var right = evalExpr(expr.right.value, env)?

    if expr.op == "+" {
        match left {
            Value::Int(leftValue) => {
                match right {
                    Value::Int(rightValue) => return Result::Ok(Value::Int(leftValue + rightValue)),
                    _ => return Result::Err(unsupported("mixed + operands")),
                }
            }
            Value::String(leftValue) => {
                match right {
                    Value::String(rightValue) => return Result::Ok(Value::String(leftValue + rightValue)),
                    _ => return Result::Err(unsupported("mixed + operands")),
                }
            }
            _ => return Result::Err(unsupported("operator +")),
        }
    }

    if expr.op == "<=" {
        match left {
            Value::Int(leftValue) => {
                match right {
                    Value::Int(rightValue) => return Result::Ok(Value::Bool(leftValue <= rightValue)),
                    _ => return Result::Err(unsupported("operator <=")),
                }
            }
            _ => return Result::Err(unsupported("operator <=")),
        }
    }

    Result::Err(unsupported("binary operator " + expr.op))
}

func lookupBinding(
    Vec[LocalBinding] env,
    String name,
) -> Result[Value, BackendError] {
    for binding in env {
        if binding.name == name {
            return Result::Ok(binding.value)
        }
    }
    Result::Err(BackendError {
        message: "undefined name " + name,
    })
}

func bindLocal(
    Vec[LocalBinding] env,
    String name,
    Value value,
) -> () {
    env.push(LocalBinding {
        name: name,
        value: value,
    })
}

func setLocal(
    Vec[LocalBinding] env,
    String name,
    Value value,
) -> () {
    var index = 0
    while index < env.len() {
        if env[index].name == name {
            env[index] = LocalBinding {
                name: name,
                value: value,
            }
            return
        }
        index = index + 1
    }
    env.push(LocalBinding {
        name: name,
        value: value,
    })
}

func hasLocal(
    Vec[LocalBinding] env,
    String name,
) -> bool {
    var index = 0
    while index < env.len() {
        if env[index].name == name {
            return true
        }
        index = index + 1
    }
    false
}

func extractCalleeName(CallExpr call) -> Result[String, BackendError] {
    match call.callee.value {
        Expr::Name(value) => Result::Ok(value.name),
        _ => Result::Err(unsupported("callee")),
    }
}

func valueToString(Value value) -> Result[String, BackendError] {
    match value {
        Value::Int(number) => Result::Ok(to_string(number)),
        Value::String(text) => Result::Ok(text),
        Value::Bool(flag) => Result::Ok(if flag { "true" } else { "false" }),
        Value::Unit(()) => Result::Ok("()"),
    }
}

func asExitCode(Value value) -> Result[int, BackendError] {
    match value {
        Value::Int(number) => Result::Ok(number),
        Value::Bool(flag) => Result::Ok(if flag { 1 } else { 0 }),
        Value::Unit(()) => Result::Ok(0),
        _ => Result::Err(unsupported("main return type")),
    }
}

func parseIntLiteral(IntExpr expr) -> int {
    parseDecimal(expr.value)
}

func unquoteString(StringExpr expr) -> String {
    var text = expr.value
    if len(text) < 2 {
        return text
    }
    slice(text, 1, len(text) - 1)
}

func hostWriteTextFile(String path, String contents) -> Result[(), BackendError] {
    match __host_write_text_file(path, contents) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => Result::Err(BackendError {
            message: err.message,
        }),
    }
}

func hostRunProcess(Vec[String] argv) -> Result[(), BackendError] {
    match __host_run_process(argv) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => Result::Err(BackendError {
            message: err.message,
        }),
    }
}

func hostMakeTempDir(String prefix) -> Result[String, BackendError] {
    match __host_make_temp_dir(prefix) {
        Result::Ok(path) => Result::Ok(path),
        Result::Err(err) => Result::Err(BackendError {
            message: err.message,
        }),
    }
}

extern "intrinsic" func __host_write_text_file(String path, String contents) -> Result[(), HostError]

extern "intrinsic" func __host_run_process(Vec[String] argv) -> Result[(), HostError]

extern "intrinsic" func __host_make_temp_dir(String prefix) -> Result[String, HostError]

func parseDecimal(String text) -> int {
    var value = 0
    var index = 0
    while index < len(text) {
        var ch = char_at(text, index)
        if ch == "_" {
            index = index + 1
            continue
        }
        value = value * 10 + digitValue(ch)
        index = index + 1
    }
    value
}

func digitValue(String ch) -> int {
    if ch == "0" {
        return 0
    }
    if ch == "1" {
        return 1
    }
    if ch == "2" {
        return 2
    }
    if ch == "3" {
        return 3
    }
    if ch == "4" {
        return 4
    }
    if ch == "5" {
        return 5
    }
    if ch == "6" {
        return 6
    }
    if ch == "7" {
        return 7
    }
    if ch == "8" {
        return 8
    }
    if ch == "9" {
        return 9
    }
    0
}

func asciiCode(String ch) -> int {
    if ch == "\n" {
        return 10
    }
    if ch == " " {
        return 32
    }
    if ch == "!" {
        return 33
    }
    if ch == "\"" {
        return 34
    }
    if ch == "," {
        return 44
    }
    if ch == "-" {
        return 45
    }
    if ch == "." {
        return 46
    }
    if ch == "(" {
        return 40
    }
    if ch == ")" {
        return 41
    }
    if ch == "[" {
        return 91
    }
    if ch == "]" {
        return 93
    }
    if ch == "{" {
        return 123
    }
    if ch == "}" {
        return 125
    }
    if ch == "_" {
        return 95
    }
    if ch == ":" {
        return 58
    }
    if ch == "/" {
        return 47
    }
    if ch == "+" {
        return 43
    }
    if ch == "0" {
        return 48
    }
    if ch == "1" {
        return 49
    }
    if ch == "2" {
        return 50
    }
    if ch == "3" {
        return 51
    }
    if ch == "4" {
        return 52
    }
    if ch == "5" {
        return 53
    }
    if ch == "6" {
        return 54
    }
    if ch == "7" {
        return 55
    }
    if ch == "8" {
        return 56
    }
    if ch == "9" {
        return 57
    }
    if ch == "A" {
        return 65
    }
    if ch == "B" {
        return 66
    }
    if ch == "C" {
        return 67
    }
    if ch == "D" {
        return 68
    }
    if ch == "E" {
        return 69
    }
    if ch == "F" {
        return 70
    }
    if ch == "G" {
        return 71
    }
    if ch == "H" {
        return 72
    }
    if ch == "I" {
        return 73
    }
    if ch == "J" {
        return 74
    }
    if ch == "K" {
        return 75
    }
    if ch == "L" {
        return 76
    }
    if ch == "M" {
        return 77
    }
    if ch == "N" {
        return 78
    }
    if ch == "O" {
        return 79
    }
    if ch == "P" {
        return 80
    }
    if ch == "Q" {
        return 81
    }
    if ch == "R" {
        return 82
    }
    if ch == "S" {
        return 83
    }
    if ch == "T" {
        return 84
    }
    if ch == "U" {
        return 85
    }
    if ch == "V" {
        return 86
    }
    if ch == "W" {
        return 87
    }
    if ch == "X" {
        return 88
    }
    if ch == "Y" {
        return 89
    }
    if ch == "Z" {
        return 90
    }
    if ch == "a" {
        return 97
    }
    if ch == "b" {
        return 98
    }
    if ch == "c" {
        return 99
    }
    if ch == "d" {
        return 100
    }
    if ch == "e" {
        return 101
    }
    if ch == "f" {
        return 102
    }
    if ch == "g" {
        return 103
    }
    if ch == "h" {
        return 104
    }
    if ch == "i" {
        return 105
    }
    if ch == "j" {
        return 106
    }
    if ch == "k" {
        return 107
    }
    if ch == "l" {
        return 108
    }
    if ch == "m" {
        return 109
    }
    if ch == "n" {
        return 110
    }
    if ch == "o" {
        return 111
    }
    if ch == "p" {
        return 112
    }
    if ch == "q" {
        return 113
    }
    if ch == "r" {
        return 114
    }
    if ch == "s" {
        return 115
    }
    if ch == "t" {
        return 116
    }
    if ch == "u" {
        return 117
    }
    if ch == "v" {
        return 118
    }
    if ch == "w" {
        return 119
    }
    if ch == "x" {
        return 120
    }
    if ch == "y" {
        return 121
    }
    if ch == "z" {
        return 122
    }
    63
}

func isTrue(Value value) -> bool {
    match value {
        Value::Bool(flag) => flag,
        Value::Int(number) => number != 0,
        Value::Unit(()) => false,
        Value::String(text) => len(text) != 0,
    }
}
