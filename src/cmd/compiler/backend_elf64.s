package compiler.backend_elf64

use compiler.internal.ssagen.MachineOp
use compiler.internal.ssagen.MachineProgram
use compiler.internal.ssagen.MachineWriteOp
use s.BlockExpr
use s.CallExpr
use s.CForStmt
use s.Expr
use s.ExprStmt
use s.FunctionDecl
use s.IntExpr
use s.IndexExpr
use s.Item
use s.MatchExpr
use s.MemberExpr
use s.Pattern
use s.VariantPattern
use s.AssignStmt
use s.IncrementStmt
use s.NameExpr
use s.ReturnStmt
use s.SourceFile
use s.Stmt
use s.StringExpr
use s.VarStmt
use s.WhileExpr
use std.fs.MakeTempDir
use std.fs.WriteTextFile
use std.option.Option
use std.prelude.Box
use std.prelude.box
use std.prelude.char_at
use std.prelude.len
use std.prelude.slice
use std.prelude.to_string
use std.process.RunProcess
use std.result.Result
use std.vec.Vec

struct Program {
    Vec[ProgramOp] ops,
    int exitCode,
}

struct WriteOp {
    int fd,
    String text,
}

struct ExitOp {
    int code,
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
    VecString(Vec[String]),
    Variant(VariantValue),
    Unit(()),
}

struct VariantValue {
    String tag,
    Option[Box[Value]] payload,
}

struct LocalBinding {
    String name,
    Value value,
}

struct BackendError {
    String message,
}

func EmitProgram(MachineProgram program, String outputPath) Result[(), BackendError] {
    var asmText = emitMachineAsm(program)
    assembleAndLink(asmText, outputPath)
}

func buildExecutable(SourceFile source, String outputPath) Result[(), BackendError] {
    // Minimal backend design:
    // 1. compile SourceFile  linear ProgramOp list
    // 2. emit Linux x86_64 assembly text
    // 3. invoke host as/ld through runtime boundary
    //
    // See /app/s/doc/backend_elf64.md for the executable MVP plan.
    //
    // The runnable algorithm still lives in backend_elf64.py today.
    var program =
        match compileProgram(source) {
            Ok(value) => value,
            Err(err) => {
                return Err(err)
            }
        }
    var asmText = emitAsm(program)
    assembleAndLink(asmText, outputPath)
}

func emitMachineAsm(MachineProgram program) String {
    emitMachineDataSection(program.ops) + "\n" + emitMachineTextSection(program) + "\n"
}

func emitMachineDataSection(Vec[MachineOp] ops) String {
    var lines = Vec[String]()
    lines.push(".section .data")
    var index = 0
    while index < ops.len() {
        match ops[index] {
            MachineOp::WriteStdout(write) => appendDataPayload(lines, "message_" + to_string(index), write.text),
            MachineOp::WriteStderr(write) => appendDataPayload(lines, "message_" + to_string(index), write.text),
            MachineOp::Exit(_) => (),
        }
        index = index + 1
    }
    joinLines(lines)
}

func emitMachineTextSection(MachineProgram program) String {
    var lines = Vec[String]()
    lines.push(".section .text")
    lines.push(".global " + program.entry_symbol)
    lines.push(program.entry_symbol + ":")
    var index = 0
    while index < program.ops.len() {
        match program.ops[index] {
            MachineOp::WriteStdout(write) => appendMachineWrite(lines, write, "message_" + to_string(index)),
            MachineOp::WriteStderr(write) => appendMachineWrite(lines, write, "message_" + to_string(index)),
            MachineOp::Exit(_) => (),
        }
        index = index + 1
    }
    lines.push("    mov $60, %rax")
    lines.push("    mov $" + to_string(program.exit_code) + ", %rdi")
    lines.push("    syscall")
    joinLines(lines)
}

func appendMachineWrite(Vec[String] lines, MachineWriteOp write, String label) () {
    lines.push("    mov $1, %rax")
    lines.push("    mov $" + to_string(write.fd) + ", %rdi")
    lines.push("    lea " + label + "(%rip), %rsi")
    lines.push("    mov $" + byteLen(write.text) + ", %rdx")
    lines.push("    syscall")
}

func compileProgram(SourceFile source) Result[Program, BackendError] {
    var mainFunc =
        match findMain(source) {
            Ok(value) => value,
            Err(err) => {
                return Err(err)
            }
        }
    var env = Vec[LocalBinding]()
    var ops = Vec[ProgramOp]()
    var exitCode =
        match executeFunction(mainFunc, env, ops) {
            Ok(value) => value,
            Err(err) => {
                return Err(err)
            }
        }
    ops.push(Exit(ExitOp {
        code: exitCode,
    }))
    Ok(Program {
        ops: ops,
        exitCode: exitCode,
    })
}

func emitAsm(Program program) String {
    emitDataSection(program.ops) + "\n" + emitTextSection(program.ops, program.exitCode) + "\n"
}

func findMain(SourceFile source) Result[FunctionDecl, BackendError] {
    for item in source.items {
        match item {
            Function(func) => {
                if func.sig.name == "main" {
                    return Ok(func)
                }
            }
            _ => (),
        }
    }
    Err(BackendError {
        message: "entry function main not found",
    })
}

func executeFunction(
    FunctionDecl func,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops
) Result[int, BackendError] {
    match func.body {
        Some(body) => executeBlock(body, env, ops),
        None => Ok(0),
    }
}

func executeBlock(
    BlockExpr body,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops
) Result[int, BackendError] {
    for stmt in body.statements {
        match stmt {
            Return(value) => return executeReturnStmt(value, env),
            _ => {
                match executeStmt(stmt, env, ops) {
                    Ok(()) => (),
                    Err(err) => {
                        return Err(err)
                    }
                }
            }
        }
    }
    match body.final_expr {
        Some(expr) => {
            var value =
                match evalExpr(expr, env) {
                    Ok(found) => found,
                    Err(err) => {
                        return Err(err)
                    }
                }
            asExitCode(value)
        }
        None => Ok(0),
    }
}

func executeStmt(
    Stmt stmt,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops
) Result[(), BackendError] {
    match stmt {
        Var(value) => executeVarStmt(value, env),
        Assign(value) => executeAssignStmt(value, env),
        Increment(value) => executeIncrementStmt(value, env),
        CFor(value) => executeCForStmt(value, env, ops),
        Expr(value) => executeExprStmt(value, env, ops),
        Return(value) => {
            value
            Ok(())
        }
    }
}

func evalExpr(
    Expr expr,
    Vec[LocalBinding] env
) Result[Value, BackendError] {
    match expr {
        Int(value) => Ok(Int(parseIntLiteral(value))),
        String(value) => Ok(String(unquoteString(value))),
        Bool(value) => Ok(Bool(value.value)),
        Index(value) => evalIndexExpr(value, env),
        Name(value) => lookupBinding(env, value.name),
        Call(value) => evalCallExpr(value, env),
        Binary(value) => evalBinaryExpr(value, env),
        Match(value) => evalMatchExpr(value, env),
        _ => Err(unsupported("backend expr")),
    }
}

func emitDataSection(Vec[ProgramOp] ops) String {
    var lines = Vec[String]()
    lines.push(".section .data")
    var index = 0
    for op in ops {
        match op {
            WriteStdout(write) => appendDataPayload(lines, "message_" + to_string(index), write.text),
            WriteStderr(write) => appendDataPayload(lines, "message_" + to_string(index), write.text),
            Exit(_) => (),
        }
        index = index + 1
    }
    joinLines(lines)
}

func emitTextSection(Vec[ProgramOp] ops, int exitCode) String {
    var lines = Vec[String]()
    lines.push(".section .text")
    lines.push(".global _start")
    lines.push("_start:")
    var index = 0
    for op in ops {
        match op {
            WriteStdout(write) => appendWriteSyscall(lines, 1, "message_" + to_string(index), write.text),
            WriteStderr(write) => appendWriteSyscall(lines, 2, "message_" + to_string(index), write.text),
            Exit(_) => (),
        }
        index = index + 1
    }
    lines.push("    mov $60, %rax")
    lines.push("    mov $" + to_string(exitCode) + ", %rdi")
    lines.push("    syscall")
    joinLines(lines)
}

func assembleAndLink(String asmText, String outputPath) Result[(), BackendError] {
    var tempDir =
        match MakeTempDir("s-build-") {
            Ok(path) => path,
            Err(err) => {
                return Err(BackendError {
                    message: err.message,
                })
            }
        }
    var asmPath = tempDir + "/out.s"
    var objPath = tempDir + "/out.o"
    match WriteTextFile(asmPath, asmText) {
        Ok(()) => (),
        Err(err) => {
            return Err(BackendError {
                message: err.message,
            })
        }
    }
    match RunProcess(Vec[String] { "as", "-o", objPath, asmPath }) {
        Ok(()) => (),
        Err(err) => {
            return Err(BackendError {
                message: err.message,
            })
        }
    }
    match RunProcess(Vec[String] { "ld", "-o", outputPath, objPath }) {
        Ok(()) => (),
        Err(err) => {
            return Err(BackendError {
                message: err.message,
            })
        }
    }
    Ok(())
}

func appendDataPayload(Vec[String] lines, String label, String text) () {
    lines.push(label + ":")
    lines.push("    .byte " + encodeBytes(text))
}

func appendWriteSyscall(Vec[String] lines, int fd, String label, String text) () {
    lines.push("    mov $1, %rax")
    lines.push("    mov $" + to_string(fd) + ", %rdi")
    lines.push("    lea " + label + "(%rip), %rsi")
    lines.push("    mov $" + byteLen(text) + ", %rdx")
    lines.push("    syscall")
}

func encodeBytes(String text) String {
    var parts = Vec[String]()
    var index = 0
    while index < len(text) {
        parts.push(to_string(asciiCode(char_at(text, index))))
        index = index + 1
    }
    joinWith(parts, ", ")
}

func byteLen(String text) String {
    // MVP: assume ASCII payloads first.
    to_string(text.len())
}

func joinLines(Vec[String] lines) String {
    joinWith(lines, "\n")
}

func joinWith(Vec[String] values, String sep) String {
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

func unsupported(String feature) BackendError {
    BackendError {
        message: "unsupported " + feature,
    }
}

func executeVarStmt(
    VarStmt stmt,
    Vec[LocalBinding] env
) Result[(), BackendError] {
    var value =
        match evalExpr(stmt.value, env) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }
    setLocal(env, stmt.name, value)
    Ok(())
}

func executeAssignStmt(
    AssignStmt stmt,
    Vec[LocalBinding] env
) Result[(), BackendError] {
    var value =
        match evalExpr(stmt.value, env) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }
    if !hasLocal(env, stmt.name) {
        return Err(BackendError {
            message: "undefined name " + stmt.name,
        })
    }
    setLocal(env, stmt.name, value)
    Ok(())
}

func executeIncrementStmt(
    IncrementStmt stmt,
    Vec[LocalBinding] env
) Result[(), BackendError] {
    var current =
        match lookupBinding(env, stmt.name) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }
    match current {
        Int(number) => {
            setLocal(env, stmt.name, Int(number + 1))
            Ok(())
        }
        _ => Err(unsupported("increment target")),
    }
}

func executeCForStmt(
    CForStmt stmt,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops
) Result[(), BackendError] {
    match executeStmt(stmt.init.value, env, ops) {
        Ok(()) => (),
        Err(err) => {
            return Err(err)
        }
    }
    var keepGoing = true
    while keepGoing {
        var condValue =
            match evalExpr(stmt.condition, env) {
                Ok(found) => found,
                Err(err) => {
                    return Err(err)
                }
            }
        if isTrue(condValue) == false {
            keepGoing = false
        } else {
            match executeBlock(stmt.body, env, ops) {
                Ok(_) => (),
                Err(err) => {
                    return Err(err)
                }
            }
            match executeStmt(stmt.step.value, env, ops) {
                Ok(()) => (),
                Err(err) => {
                    return Err(err)
                }
            }
        }
    }
    Ok(())
}

func executeExprStmt(
    ExprStmt stmt,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops
) Result[(), BackendError] {
    match stmt.expr {
        Call(value) => executeCallStmt(value, env, ops),
        While(value) => executeWhileExpr(value, env, ops),
        _ => {
            match evalExpr(stmt.expr, env) {
                Ok(_) => (),
                Err(err) => {
                    return Err(err)
                }
            }
            Ok(())
        }
    }
}

func executeCallStmt(
    CallExpr call,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops
) Result[(), BackendError] {
    match call.callee.value {
        Member(member) => return executeMemberCallStmt(member, call.args, env),
        _ => (),
    }
    var calleeName =
        match extractCalleeName(call) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }
    if len(call.args) != 1 {
        return Err(unsupported("call arity"))
    }
    var value =
        match evalExpr(call.args[0], env) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }
    var text =
        match valueToString(value) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }

    if calleeName == "println" {
        ops.push(WriteStdout(WriteOp {
            fd: 1,
            text: text + "\n",
        }))
        return Ok(())
    }
    if calleeName == "eprintln" {
        ops.push(WriteStderr(WriteOp {
            fd: 2,
            text: text + "\n",
        }))
        return Ok(())
    }
    Err(unsupported("call " + calleeName))
}

func executeMemberCallStmt(
    MemberExpr member,
    Vec[Expr] args,
    Vec[LocalBinding] env
) Result[(), BackendError] {
    match member.target.value {
        Name(nameExpr) => {
            if member.member == "push" {
                if len(args) != 1 {
                    return Err(unsupported("call arity"))
                }
                var current =
                    match lookupBinding(env, nameExpr.name) {
                        Ok(found) => found,
                        Err(err) => {
                            return Err(err)
                        }
                    }
                var nextValue =
                    match evalExpr(args[0], env) {
                        Ok(found) => found,
                        Err(err) => {
                            return Err(err)
                        }
                    }
                match current {
                    VecString(items) => {
                        match nextValue {
                            String(text) => {
                                items.push(text)
                                setLocal(env, nameExpr.name, VecString(items))
                                return Ok(())
                            }
                            _ => return Err(unsupported("vec push payload")),
                        }
                    }
                    _ => return Err(unsupported("method " + member.member)),
                }
            }
            Err(unsupported("method " + member.member))
        }
        _ => Err(unsupported("method receiver")),
    }
}

func executeWhileExpr(
    WhileExpr expr,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops
) Result[(), BackendError] {
    var keepGoing = true
    while keepGoing {
        var condValue =
            match evalExpr(expr.condition.value, env) {
                Ok(found) => found,
                Err(err) => {
                    return Err(err)
                }
            }
        if isTrue(condValue) == false {
            keepGoing = false
        } else {
            match executeBlock(expr.body, env, ops) {
                Ok(_) => (),
                Err(err) => {
                    return Err(err)
                }
            }
        }
    }
    Ok(())
}

func executeReturnStmt(
    ReturnStmt stmt,
    Vec[LocalBinding] env
) Result[int, BackendError] {
    match stmt.value {
        Some(expr) => {
            var value =
                match evalExpr(expr, env) {
                    Ok(found) => found,
                    Err(err) => {
                        return Err(err)
                    }
                }
            asExitCode(value)
        }
        None => Ok(0),
    }
}

func evalCallExpr(
    CallExpr call,
    Vec[LocalBinding] env
) Result[Value, BackendError] {
    match call.callee.value {
        Name(nameExpr) => {
            if nameExpr.name == "Vec" {
                if len(call.args) == 0 {
                    return Ok(VecString(Vec[String]()))
                }
                return Err(unsupported("vec constructor arity"))
            }
            if nameExpr.name == "Some" || nameExpr.name == "Ok" || nameExpr.name == "Err" {
                if len(call.args) != 1 {
                    return Err(unsupported("variant constructor arity"))
                }
                var payload =
                    match evalExpr(call.args[0], env) {
                        Ok(found) => found,
                        Err(err) => {
                            return Err(err)
                        }
                    }
                return Ok(Variant(VariantValue {
                    tag: nameExpr.name,
                    payload: Some(box(payload)),
                }))
            }
            Err(unsupported("call " + nameExpr.name))
        }
        Index(indexExpr) => {
            match indexExpr.target.value {
                Name(nameExpr) => {
                    if nameExpr.name == "Vec" && len(call.args) == 0 {
                        return Ok(VecString(Vec[String]()))
                    }
                    Err(unsupported("callee"))
                }
                _ => Err(unsupported("callee")),
            }
        }
        Member(memberExpr) => evalMemberCallExpr(memberExpr, call.args, env),
        _ => Err(unsupported("callee")),
    }
}

func evalMemberCallExpr(
    MemberExpr member,
    Vec[Expr] args,
    Vec[LocalBinding] env
) Result[Value, BackendError] {
    var receiver =
        match evalExpr(member.target.value, env) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }
    if member.member == "len" {
        if len(args) != 0 {
            return Err(unsupported("call arity"))
        }
        match receiver {
            VecString(items) => return Ok(Int(items.len())),
            String(text) => return Ok(Int(text.len())),
            _ => return Err(unsupported("method len")),
        }
    }
    if member.member == "push" {
        match executeMemberCallStmt(member, args, env) {
            Ok(()) => (),
            Err(err) => {
                return Err(err)
            }
        }
        return Ok(Unit(()))
    }
    Err(unsupported("method " + member.member))
}

struct PatternMatch {
    bool matched,
    Vec[LocalBinding] bindings,
}

func evalMatchExpr(
    MatchExpr expr,
    Vec[LocalBinding] env
) Result[Value, BackendError] {
    var subject =
        match evalExpr(expr.subject.value, env) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }
    for arm in expr.arms {
        var matchResult =
            match matchPattern(arm.pattern, subject) {
                Ok(found) => found,
                Err(err) => {
                    return Err(err)
                }
            }
        if matchResult.matched {
            var armEnv = cloneEnv(env)
            applyBindings(armEnv, matchResult.bindings)
            var value =
                match evalExpr(arm.expr, armEnv) {
                    Ok(found) => found,
                    Err(err) => {
                        return Err(err)
                    }
                }
            syncExistingBindings(env, armEnv)
            return Ok(value)
        }
    }
    Err(unsupported("match fallthrough"))
}

func matchPattern(
    Pattern pattern,
    Value value
) Result[PatternMatch, BackendError] {
    match pattern {
        Wildcard(_) => Ok(PatternMatch {
            matched: true,
            bindings: Vec[LocalBinding](),
        }),
        Name(name) => Ok(PatternMatch {
            matched: true,
            bindings: Vec[LocalBinding] {
                LocalBinding {
                    name: name.name,
                    value: value,
                },
            },
        }),
        Variant(variant) => matchVariantPattern(variant, value),
    }
}

func matchVariantPattern(
    VariantPattern pattern,
    Value value
) Result[PatternMatch, BackendError] {
    match value {
        Variant(variant) => {
            if lastPathSegment(pattern.path) != variant.tag {
                return Ok(PatternMatch {
                    matched: false,
                    bindings: Vec[LocalBinding](),
                })
            }
            if len(pattern.args) == 0 {
                return Ok(PatternMatch {
                    matched: true,
                    bindings: Vec[LocalBinding](),
                })
            }
            match variant.payload {
                Some(payload) => {
                    if len(pattern.args) != 1 {
                        return Err(unsupported("variant pattern arity"))
                    }
                    return matchPattern(pattern.args[0], payload.value)
                }
                None => Ok(PatternMatch {
                    matched: false,
                    bindings: Vec[LocalBinding](),
                }),
            }
        }
        _ => Ok(PatternMatch {
            matched: false,
            bindings: Vec[LocalBinding](),
        }),
    }
}

func evalIndexExpr(
    IndexExpr expr,
    Vec[LocalBinding] env
) Result[Value, BackendError] {
    var target =
        match evalExpr(expr.target.value, env) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }
    var index =
        match evalExpr(expr.index.value, env) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }
    match index {
        Int(pos) => {
            match target {
                VecString(items) => Ok(String(items[pos])),
                _ => Err(unsupported("index target")),
            }
        }
        _ => Err(unsupported("index value")),
    }
}

func evalBinaryExpr(
    s.BinaryExpr expr,
    Vec[LocalBinding] env
) Result[Value, BackendError] {
    var left =
        match evalExpr(expr.left.value, env) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }
    var right =
        match evalExpr(expr.right.value, env) {
            Ok(found) => found,
            Err(err) => {
                return Err(err)
            }
        }

    if expr.op == "+" {
        match left {
            Int(leftValue) => {
                match right {
                    Int(rightValue) => return Ok(Int(leftValue + rightValue)),
                    _ => return Err(unsupported("mixed + operands")),
                }
            }
            String(leftValue) => {
                match right {
                    String(rightValue) => return Ok(String(leftValue + rightValue)),
                    _ => return Err(unsupported("mixed + operands")),
                }
            }
            _ => return Err(unsupported("operator +")),
        }
    }

    if expr.op == "<=" {
        match left {
            Int(leftValue) => {
                match right {
                    Int(rightValue) => return Ok(Bool(leftValue <= rightValue)),
                    _ => return Err(unsupported("operator <=")),
                }
            }
            _ => return Err(unsupported("operator <=")),
        }
    }

    Err(unsupported("binary operator " + expr.op))
}

func lookupBinding(
    Vec[LocalBinding] env,
    String name
) Result[Value, BackendError] {
    if name == "None" {
        return Ok(Variant(VariantValue {
            tag: "None",
            payload: None,
        }))
    }
    for binding in env {
        if binding.name == name {
            return Ok(binding.value)
        }
    }
    Err(BackendError {
        message: "undefined name " + name,
    })
}

func cloneEnv(Vec[LocalBinding] env) Vec[LocalBinding] {
    var copied = Vec[LocalBinding]()
    for binding in env {
        copied.push(LocalBinding {
            name: binding.name,
            value: binding.value,
        })
    }
    copied
}

func applyBindings(
    Vec[LocalBinding] env,
    Vec[LocalBinding] bindings
) () {
    for binding in bindings {
        setLocal(env, binding.name, binding.value)
    }
}

func syncExistingBindings(
    Vec[LocalBinding] env,
    Vec[LocalBinding] source
) () {
    var index = 0
    while index < env.len() {
        match lookupBinding(source, env[index].name) {
            Ok(value) => {
                env[index] = LocalBinding {
                    name: env[index].name,
                    value: value,
                }
            }
            Err(_) => (),
        }
        index = index + 1
    }
}

func bindLocal(
    Vec[LocalBinding] env,
    String name,
    Value value
) () {
    env.push(LocalBinding {
        name: name,
        value: value,
    })
}

func setLocal(
    Vec[LocalBinding] env,
    String name,
    Value value
) () {
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
    String name
) bool {
    var index = 0
    while index < env.len() {
        if env[index].name == name {
            return true
        }
        index = index + 1
    }
    false
}

func extractCalleeName(CallExpr call) Result[String, BackendError] {
    match call.callee.value {
        Name(value) => Ok(value.name),
        _ => Err(unsupported("callee")),
    }
}

func valueToString(Value value) Result[String, BackendError] {
    match value {
        Int(number) => Ok(to_string(number)),
        String(text) => Ok(text),
        Bool(flag) => Ok(if flag { "true" } else { "false" }),
        VecString(_) => Err(unsupported("stringify vec")),
        Variant(variant) => {
            match variant.payload {
                Some(payload) => {
                    var text =
                        match valueToString(payload.value) {
                            Ok(found) => found,
                            Err(err) => {
                                return Err(err)
                            }
                        }
                    Ok(variant.tag + "(" + text + ")")
                }
                None => Ok(variant.tag),
            }
        }
        Unit(()) => Ok("()"),
    }
}

func asExitCode(Value value) Result[int, BackendError] {
    match value {
        Int(number) => Ok(number),
        Bool(flag) => Ok(if flag { 1 } else { 0 }),
        Unit(()) => Ok(0),
        _ => Err(unsupported("main return type")),
    }
}

func parseIntLiteral(IntExpr expr) int {
    parseDecimal(expr.value)
}

func unquoteString(StringExpr expr) String {
    var text = expr.value
    if len(text) < 2 {
        return text
    }
    slice(text, 1, len(text) - 1)
}


func parseDecimal(String text) int {
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

func digitValue(String ch) int {
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

func asciiCode(String ch) int {
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

func isTrue(Value value) bool {
    match value {
        Bool(flag) => flag,
        Int(number) => number != 0,
        Unit(()) => false,
        VecString(items) => items.len() != 0,
        Variant(_) => true,
        String(text) => len(text) != 0,
    }
}

func lastPathSegment(String path) String {
    var index = len(path) - 1
    while index >= 0 {
        var ch = char_at(path, index)
        if ch == ":" {
            if index > 0 {
                if char_at(path, index - 1) == ":" {
                    return slice(path, index + 1, len(path))
                }
            }
        }
        index = index - 1
    }
    path
}
