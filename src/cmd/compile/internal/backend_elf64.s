package compile.internal.backend_elf64

use compile.internal.semantic.CheckText
use compile.internal.syntax.ParseSource
use s.AssignStmt
use s.BinaryExpr
use s.BlockExpr
use s.BoolExpr
use s.CForStmt
use s.CallExpr
use s.Expr
use s.ExprStmt
use s.FunctionDecl
use s.IfExpr
use s.IncrementStmt
use s.IntExpr
use s.Item
use s.NameExpr
use s.SourceFile
use s.Stmt
use s.StringExpr
use s.VarStmt
use s.WhileExpr
use std.fs.MakeTempDir
use std.fs.ReadToString
use std.fs.WriteTextFile
use std.io.eprintln
use std.option.Option
use std.process.RunProcess
use std.prelude.charAt
use std.prelude.len
use std.prelude.toString
use std.vec.Vec

struct BackendError {
    string message,
}

func okFunction(FunctionDecl value) Result[FunctionDecl, BackendError] {
    Result.Ok(value);
}

func failFunction(string message) Result[FunctionDecl, BackendError] {
    Result.Err(BackendError {
        message: message,
    });
}

func okWriteOps(Vec[WriteOp] value) Result[Vec[WriteOp], BackendError] {
    Result.Ok(value);
}

func failWriteOps(string message) Result[Vec[WriteOp], BackendError] {
    Result.Err(BackendError {
        message: message,
    });
}

func okValue(Value value) Result[Value, BackendError] {
    Result.Ok(value);
}

func failValue(string message) Result[Value, BackendError] {
    Result.Err(BackendError {
        message: message,
    });
}

func okUnit() Result[(), BackendError] {
    Result.Ok(());
}

func failUnit(string message) Result[(), BackendError] {
    Result.Err(BackendError {
        message: message,
    });
}

func okInt(int32 value) Result[int32, BackendError] {
    Result.Ok(value);
}

func failInt(string message) Result[int32, BackendError] {
    Result.Err(BackendError {
        message: message,
    });
}

struct UnitValue {}

enum Value {
    Int(int32),
    String(string),
    Bool(bool),
    Unit(UnitValue),
}

struct Binding {
    string name,
    Value value,
}

struct WriteOp {
    int32 fd,
    string text,
}

func Build(string path, string output) int32 {
    var sourceResult = ReadToString(path)
    if sourceResult.isErr() {
        return reportFailure("failed to read source file: " + path + ": " + sourceResult.unwrapErr().message)
    }

    var source = sourceResult.unwrap()
    var parsedResult = ParseSource(source)
    if parsedResult.isErr() {
        return reportFailure("parse failed: " + parsedResult.unwrapErr().message)
    }

    if CheckText(source) != 0 {
        return reportFailure("semantic check failed")
    }

    var writesResult = compileWrites(parsedResult.unwrap())
    if writesResult.isErr() {
        return reportFailure(writesResult.unwrapErr().message)
    }

    var exitCodeResult = compileExitCode(parsedResult.unwrap())
    if exitCodeResult.isErr() {
        return reportFailure(exitCodeResult.unwrapErr().message)
    }

    var asmText = emitAsm(writesResult.unwrap(), exitCodeResult.unwrap())
    var tempDirResult = MakeTempDir("s-build-")
    if tempDirResult.isErr() {
        return reportFailure("could not create temporary output directory: " + tempDirResult.unwrapErr().message)
    }

    var tempDir = tempDirResult.unwrap()
    var asmPath = tempDir + "/out.s"
    var objPath = tempDir + "/out.o"

    var writeResult = WriteTextFile(asmPath, asmText)
    if writeResult.isErr() {
        return reportFailure("failed to write assembly: " + writeResult.unwrapErr().message)
    }

    var asArgv = Vec[string]()
    asArgv.push("as");
    asArgv.push("-o");
    asArgv.push(objPath);
    asArgv.push(asmPath);
    var asResult = RunProcess(asArgv)
    if asResult.isErr() {
        return reportFailure("toolchain failed: " + asResult.unwrapErr().message)
    }

    var ldArgv = Vec[string]()
    ldArgv.push("ld");
    ldArgv.push("-o");
    ldArgv.push(output);
    ldArgv.push(objPath);
    var ldResult = RunProcess(ldArgv)
    if ldResult.isErr() {
        return reportFailure("toolchain failed: " + ldResult.unwrapErr().message)
    }

    0
}

func compileWrites(SourceFile source) Result[Vec[WriteOp], BackendError] {
    match findMain(source) {
        Result.Err(err) => Result.Err(err),
        Result.Ok(mainFunction) => {
            var writes = Vec[WriteOp]()
            var mainResultValue = callFunction(source, mainFunction.sig.name, Vec[Value](), writes)
            match mainResultValue {
                Result.Err(err) => Result.Err(err),
                Result.Ok(value) => {
                    Result.Ok(writes)
                }
            }
        }
    }
}

func compileExitCode(SourceFile source) Result[int32, BackendError] {
    match findMain(source) {
        Result.Err(err) => Result.Err(err),
        Result.Ok(mainFunction) => {
            var writes = Vec[WriteOp]()
            var mainResultValue = callFunction(source, mainFunction.sig.name, Vec[Value](), writes)
            match mainResultValue {
                Result.Err(err) => Result.Err(err),
                Result.Ok(value) => valueToExitCode(value),
            }
        }
    }
}

func findMain(SourceFile source) Result[FunctionDecl, BackendError] {
    var i = 0
    while i < source.items.len() {
        match source.items[i] {
            Item.Function(value) => {
                if value.body.isSome() && (value.sig.name == "main" || value.sig.name == "Main") {
                    okFunction(value)
                }
            }
            _ => (),
        }
        i = i + 1
    }
    failFunction("backend error: entry function main not found")
}

func callFunction(SourceFile source, string name, Vec[Value] args, Vec[WriteOp] mut writes) Result[Value, BackendError] {
    var fnResult = findFunction(source, name)
    if fnResult.isErr() {
        return failValue(fnResult.unwrapErr().message)
    }

    var function = fnResult.unwrap()
    if function.body.isNone() {
        return failValue("backend error: function " + name + " has no body")
    }
    if function.sig.params.len() != args.len() {
        return failValue(
            "backend error: function "
                + name
                + " expects "
                + toString(function.sig.params.len())
                + " args, got "
                + toString(args.len())
        )
    }

    var env = Vec[Binding]()
    var pi = 0
    while pi < function.sig.params.len() {
        env.push(Binding {
            name: function.sig.params[pi].name,
            value: args[pi],
        })
        pi = pi + 1
    }

    var bodyResult = executeBlockInPlace(function.body.unwrap(), source, env, writes)
    if bodyResult.isErr() {
        return failValue(bodyResult.unwrapErr().message)
    }
    okValue(bodyResult.unwrap())
}

func findFunction(SourceFile source, string name) Result[FunctionDecl, BackendError] {
    var i = 0
    while i < source.items.len() {
        match source.items[i] {
            Item.Function(value) => {
                if value.sig.name == name {
                    Result::Ok(value)
                }
            }
            _ => (),
        }
        i = i + 1
    }
    Result::Err(BackendError { message: "backend error: unknown function " + name })
}

func executeBlock(BlockExpr block, SourceFile source, Vec[Binding] mut env, Vec[WriteOp] mut writes) Result[Value, BackendError] {
    var localEnv = copyBindings(env)
    var result = executeBlockInPlace(block, source, localEnv, writes)
    if result.isErr() {
        Result::Err(result.unwrapErr())
    }
    Result::Ok(result.unwrap())
}

func executeBlockInPlace(BlockExpr block, SourceFile source, Vec[Binding] mut env, Vec[WriteOp] mut writes) Result[Value, BackendError] {
    var si = 0
    while si < block.statements.len() {
        var stmtResult = executeStmt(block.statements[si], source, env, writes)
        if stmtResult.isErr() {
            Result::Err(stmtResult.unwrapErr())
        }
        si = si + 1
    }

    match block.finalExpr {
        Option.Some(expr) => evalExpr(expr, source, env, ops),
        Option.None => Result::Ok(Value::Unit(UnitValue {})),
    }
}

func executeStmt(Stmt stmt, SourceFile source, Vec[Binding] mut env, Vec[WriteOp] mut writes) Result[(), BackendError] {
    match stmt {
        Stmt.Var(value) => {
            var exprResult = evalExpr(value.value, source, env, writes)
            if exprResult.isErr() {
                Result::Err(exprResult.unwrapErr())
            }
            env.push(Binding {
                name: value.name,
                value: exprResult.unwrap(),
            })
            Result::Ok(())
        }
        Stmt.Assign(value) => {
            var exprResult = evalExpr(value.value, source, env, writes)
            if exprResult.isErr() {
                Result::Err(exprResult.unwrapErr())
            }
            var index = findBindingIndex(env, value.name)
            if index < 0 {
                Result::Err(BackendError { message: "backend error: unknown name " + value.name })
            }
            env.set(index, Binding {
                name: value.name,
                value: exprResult.unwrap(),
            })
            Result::Ok(())
        }
        Stmt.Increment(value) => {
            var index = findBindingIndex(env, value.name)
            if index < 0 {
                Result::Err(BackendError { message: "backend error: unknown name " + value.name })
            }
            var current = env.get(index).unwrap().value
            match current {
                Value.Int(number) => {
                    env.set(index, Binding {
                        name: value.name,
                        value: Value.Int(number + 1),
                    })
                    Result::Ok(())
                }
                _ => Result::Err(BackendError { message: "backend error: increment expects int32 for " + value.name }),
            }
        }
        Stmt.CFor(value) => executeCFor(value, source, env, writes),
        Stmt.Return(_) => Result::Err(BackendError { message: "backend error: return statements are not supported in the MVP backend" }),
        Stmt.Expr(value) => {
            var exprResult = evalExpr(value.expr, source, env, writes)
            if exprResult.isErr() {
                Result::Err(exprResult.unwrapErr())
            }
            Result::Ok(())
        }
        Stmt.Defer(_) => Result::Err(BackendError { message: "backend error: defer statements are not supported in the MVP backend" }),
    }
}

func executeCFor(CForStmt value, SourceFile source, Vec[Binding] mut env, Vec[WriteOp] mut writes) Result[(), BackendError] {
    var loopEnv = copyBindings(env)

    var initResult = executeStmt(value.init.value, source, loopEnv, writes)
    if initResult.isErr() {
        Result::Err(initResult.unwrapErr())
    }

    while true {
        var condResult = evalExpr(value.condition, source, loopEnv, writes)
        if condResult.isErr() {
            Result::Err(condResult.unwrapErr())
        }
        var condValue = condResult.unwrap()
        match condValue {
            Value.Bool(flag) => {
                if !flag {
                    break
                }
            }
            _ => Result::Err(BackendError { message: "backend error: for condition must be bool" }),
        }

        var bodyResult = executeBlockInPlace(value.body, source, loopEnv, writes)
        if bodyResult.isErr() {
            Result::Err(bodyResult.unwrapErr())
        }

        var stepResult = executeStmt(value.step.value, source, loopEnv, writes)
        if stepResult.isErr() {
            Result::Err(stepResult.unwrapErr())
        }
    }

    propagateBindings(env, loopEnv)
    Result::Ok(())
}

func evalExpr(Expr expr, SourceFile source, Vec[Binding] mut env, Vec[WriteOp] mut writes) Result[Value, BackendError] {
    match expr {
        Expr.Int(value) => Result::Ok(Value.Int(parseIntLiteral(value.value))),
        Expr.string(value) => Result::Ok(Value.String(decodeStringLiteral(value.value))),
        Expr.Bool(value) => Result::Ok(Value.Bool(value.value)),
        Expr.Name(value) => lookupValue(env, value.name),
        Expr.Binary(value) => evalBinary(value, source, env, writes),
        Expr.Call(value) => evalCall(value, source, env, writes),
        Expr.If(value) => evalIfExpr(value, source, env, writes),
        Expr.While(value) => evalWhileExpr(value, source, env, writes),
        Expr.Block(value) => executeBlock(value, source, env, writes),
        Expr.For(_) => Result::Err(BackendError { message: "backend error: for expressions are not supported in the MVP backend" }),
        Expr.Match(_) => Result::Err(BackendError { message: "backend error: match expressions are not supported in the MVP backend" }),
        Expr.Borrow(_) => Result::Err(BackendError { message: "backend error: borrow expressions are not supported in the MVP backend" }),
        Expr.Member(_) => Result::Err(BackendError { message: "backend error: member expressions are not supported in the MVP backend" }),
        Expr.Index(_) => Result::Err(BackendError { message: "backend error: index expressions are not supported in the MVP backend" }),
        Expr.Array(_) => Result::Err(BackendError { message: "backend error: array literals are not supported in the MVP backend" }),
        Expr.Map(_) => Result::Err(BackendError { message: "backend error: map literals are not supported in the MVP backend" }),
    }
}

func evalBinary(BinaryExpr value, SourceFile source, Vec[Binding] mut env, Vec[WriteOp] mut writes) Result[Value, BackendError] {
    var leftResult = evalExpr(value.left.value, source, env, writes)
    if leftResult.isErr() {
        Result::Err(leftResult.unwrapErr())
    }
    var rightResult = evalExpr(value.right.value, source, env, writes)
    if rightResult.isErr() {
        Result::Err(rightResult.unwrapErr())
    }

    var left = leftResult.unwrap()
    var right = rightResult.unwrap()

    match value.op {
        "+" => addValues(left, right),
        "-" => numericBinary(left, right, value.op),
        "*" => numericBinary(left, right, value.op),
        "/" => numericBinary(left, right, value.op),
        "==" => compareValues(left, right, true),
        "!=" => compareValues(left, right, false),
        "<" => orderedCompare(left, right, value.op),
        "<=" => orderedCompare(left, right, value.op),
        ">" => orderedCompare(left, right, value.op),
        ">=" => orderedCompare(left, right, value.op),
        "&&" => logicalBinary(left, right, true),
        "||" => logicalBinary(left, right, false),
        _ => Result::Err(BackendError { message: "backend error: unsupported binary operator " + value.op }),
    }
}

func evalCall(CallExpr value, SourceFile source, Vec[Binding] mut env, Vec[WriteOp] mut writes) Result[Value, BackendError] {
    match value.callee.value {
        Expr.Name(calleeName) => {
            if calleeName.name == "println" || calleeName.name == "eprintln" {
                return evalPrintCall(calleeName.name, value.args, source, env, writes)
            }

            var argValues = Vec[Value]()
            var ai = 0
            while ai < value.args.len() {
                var argResult = evalExpr(value.args[ai], source, env, writes)
                if argResult.isErr() {
                    Result::Err(argResult.unwrapErr())
                }
                argValues.push(argResult.unwrap())
                ai = ai + 1
            }
            callFunction(source, calleeName.name, argValues, writes)
        }
        _ => Result::Err(BackendError { message: "backend error: unsupported call target" }),
    }
}

func evalPrintCall(string name, Vec[Expr] args, SourceFile source, Vec[Binding] mut env, Vec[WriteOp] mut writes) Result[Value, BackendError] {
    if args.len() > 1 {
        Result::Err(BackendError { message: "backend error: " + name + " expects at most one argument" })
    }

    var text = ""
    if args.len() == 1 {
        var argResult = evalExpr(args[0], source, env, writes)
        if argResult.isErr() {
            Result::Err(argResult.unwrapErr())
        }
        text = stringifyValue(argResult.unwrap())
    }

    var opText = text + "\n"
    if name == "println" {
        writes.push(WriteOp { fd: 1, text: opText });
    } else {
        writes.push(WriteOp { fd: 2, text: opText });
    }
    Result::Ok(Value.Unit(UnitValue {}))
}

func evalIfExpr(IfExpr value, SourceFile source, Vec[Binding] mut env, Vec[WriteOp] mut writes) Result[Value, BackendError] {
    var condResult = evalExpr(value.condition.value, source, env, writes)
    if condResult.isErr() {
        Result::Err(condResult.unwrapErr())
    }

    match condResult.unwrap() {
        Value.Bool(flag) => {
            if flag {
                executeBlockInPlace(value.thenBranch, source, env, writes)
            } else {
                match value.elseBranch {
                    Option.Some(expr) => evalExpr(expr.value, source, env, writes),
                    Option.None => Result::Ok(Value.Unit(UnitValue {})),
                }
            }
        }
        _ => Result::Err(BackendError { message: "backend error: if condition must be bool" }),
    }
}

func evalWhileExpr(WhileExpr value, SourceFile source, Vec[Binding] mut env, Vec[WriteOp] mut writes) Result[Value, BackendError] {
    while true {
        var condResult = evalExpr(value.condition.value, source, env, writes)
        if condResult.isErr() {
            Result::Err(condResult.unwrapErr())
        }
        match condResult.unwrap() {
            Value.Bool(flag) => {
                if !flag {
                    break
                }
            }
            _ => Result::Err(BackendError { message: "backend error: while condition must be bool" }),
        }

        var bodyResult = executeBlockInPlace(value.body, source, env, writes)
        if bodyResult.isErr() {
            Result::Err(bodyResult.unwrapErr())
        }
    }
    Result::Ok(Value.Unit(UnitValue {}))
}

func lookupValue(Vec[Binding] env, string name) Result[Value, BackendError] {
    var index = findBindingIndex(env, name)
    if index < 0 {
        Result::Err(BackendError { message: "backend error: unknown name " + name })
    }
    Result::Ok(env[index].value)
}

func addValues(Value left, Value right) Result[Value, BackendError] {
    match left {
        Value.Int(leftInt) => {
            match right {
                Value.Int(rightInt) => Result::Ok(Value.Int(leftInt + rightInt)),
                _ => Result::Err(BackendError { message: "backend error: + expects matching types" }),
            }
        }
        Value.String(leftText) => {
            match right {
                Value.String(rightText) => Result::Ok(Value.String(leftText + rightText)),
                _ => Result::Err(BackendError { message: "backend error: + expects matching string types" }),
            }
        }
        _ => Result::Err(BackendError { message: "backend error: unsupported + operands" }),
    }
}

func numericBinary(Value left, Value right, string op) Result[Value, BackendError] {
    match left {
        Value.Int(leftInt) => {
            match right {
                Value.Int(rightInt) => {
                    if op == "-" {
                        Result::Ok(Value.Int(leftInt - rightInt))
                    } else if op == "*" {
                        Result::Ok(Value.Int(leftInt * rightInt))
                    } else if op == "/" {
                        if rightInt == 0 {
                            Result::Err(BackendError { message: "backend error: division by zero" })
                        } else {
                            Result::Ok(Value.Int(leftInt / rightInt))
                        }
                    } else {
                        Result::Err(BackendError { message: "backend error: unsupported numeric operator " + op })
                    }
                }
                _ => Result::Err(BackendError { message: "backend error: numeric operator expects int32 operands" }),
            }
        }
        _ => Result::Err(BackendError { message: "backend error: numeric operator expects int32 operands" }),
    }
}

func compareValues(Value left, Value right, bool equal) Result[Value, BackendError] {
    var same = false
    match left {
        Value.Int(leftInt) => {
            match right {
                Value.Int(rightInt) => same = leftInt == rightInt,
                _ => Result::Err(BackendError { message: "backend error: comparison expects matching types" }),
            }
        }
        Value.String(leftText) => {
            match right {
                Value.String(rightText) => same = leftText == rightText,
                _ => Result::Err(BackendError { message: "backend error: comparison expects matching types" }),
            }
        }
        Value.Bool(leftBool) => {
            match right {
                Value.Bool(rightBool) => same = leftBool == rightBool,
                _ => Result::Err(BackendError { message: "backend error: comparison expects matching types" }),
            }
        }
        Value.Unit(_) => {
            match right {
                Value.Unit(_) => same = true,
                _ => Result::Err(BackendError { message: "backend error: comparison expects matching types" }),
            }
        }
    }

    if equal {
        Result::Ok(Value.Bool(same))
    } else {
        Result::Ok(Value.Bool(!same))
    }
}

func orderedCompare(Value left, Value right, string op) Result[Value, BackendError] {
    match left {
        Value.Int(leftInt) => {
            match right {
                Value.Int(rightInt) => {
                    if op == "<" {
                        Result::Ok(Value.Bool(leftInt < rightInt))
                    } else if op == "<=" {
                        Result::Ok(Value.Bool(leftInt <= rightInt))
                    } else if op == ">" {
                        Result::Ok(Value.Bool(leftInt > rightInt))
                    } else if op == ">=" {
                        Result::Ok(Value.Bool(leftInt >= rightInt))
                    } else {
                        Result::Err(BackendError { message: "backend error: unsupported ordered comparison " + op })
                    }
                }
                _ => Result::Err(BackendError { message: "backend error: ordered comparison expects int32 operands" }),
            }
        }
        _ => Result::Err(BackendError { message: "backend error: ordered comparison expects int32 operands" }),
    }
}

func logicalBinary(Value left, Value right, bool andOp) Result[Value, BackendError] {
    match left {
        Value.Bool(leftBool) => {
            match right {
                Value.Bool(rightBool) => {
                    if andOp {
                        Result::Ok(Value.Bool(leftBool && rightBool))
                    } else {
                        Result::Ok(Value.Bool(leftBool || rightBool))
                    }
                }
                _ => Result::Err(BackendError { message: "backend error: logical operator expects bool operands" }),
            }
        }
        _ => Result::Err(BackendError { message: "backend error: logical operator expects bool operands" }),
    }
}

func valueToExitCode(Value value) Result[int32, BackendError] {
    match value {
        Value.Int(number) => Result::Ok(number),
        Value.Bool(flag) => Result::Ok(if flag { 1 } else { 0 }),
        Value.Unit(_) => Result::Ok(0),
        Value.String(_) => Result::Err(BackendError { message: "backend error: main cannot return string" }),
    }
}

func stringifyValue(Value value) string {
    match value {
        Value.Int(number) => toString(number),
        Value.String(text) => text,
        Value.Bool(flag) => if flag { "true" } else { "false" },
        Value.Unit(_) => "()",
    }
}

func parseIntLiteral(string literal) int32 {
    var value = literal
    var sign = 1
    var index = 0
    if len(value) > 0 && charAt(value, 0) == "-" {
        sign = -1
        index = 1
    }

    var out = 0
    while index < len(value) {
        var ch = charAt(value, index)
        if ch != "_" {
            var digit = digitValue(ch)
            if digit < 0 {
                return 0
            }
            out = out * 10 + digit
        }
        index = index + 1
    }
    sign * out
}

func digitValue(string ch) int32 {
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
    -1
}

func decodeStringLiteral(string literal) string {
    var text = literal
    if len(text) < 2 {
        return text
    }

    var out = ""
    var index = 1
    while index < len(text) - 1 {
        var ch = charAt(text, index)
        if ch != "\\" {
            out = out + ch
            index = index + 1
            continue
        }

        if index + 1 >= len(text) - 1 {
            out = out + "\\"
            break
        }

        var esc = charAt(text, index + 1)
        if esc == "n" {
            out = out + "\n"
        } else if esc == "t" {
            out = out + "\t"
        } else if esc == "r" {
            out = out + "\r"
        } else if esc == "\"" {
            out = out + "\""
        } else if esc == "\\" {
            out = out + "\\"
        } else {
            out = out + esc
        }
        index = index + 2
    }
    out
}

func emitAsm(Vec[WriteOp] writes, int32 exitCode) string {
    var dataLines = Vec[string]()
    var textLines = Vec[string]()
    dataLines.push(".section .data")
    textLines.push(".section .text")
    textLines.push(".global _start")
    textLines.push("_start:")

    var messageIndex = 0
    var i = 0
    while i < writes.len() {
        appendWriteOp(dataLines, textLines, writes[i], messageIndex)
        messageIndex = messageIndex + 1
        i = i + 1
    }

    textLines.push("    mov $60, %rax")
    textLines.push("    mov $" + toString(exitCode) + ", %rdi")
    textLines.push("    syscall")

    joinLines(dataLines) + "\n\n" + joinLines(textLines) + "\n"
}

func appendWriteOp(Vec[string] dataLines, Vec[string] textLines, WriteOp op, int32 index) () {
    var label = "message_" + toString(index)
    dataLines.push(label + ":")
    dataLines.push("    .ascii \"" + escapeAsmString(op.text) + "\"")
    textLines.push("    mov $1, %rax")
    textLines.push("    mov $" + toString(op.fd) + ", %rdi")
    textLines.push("    lea " + label + "(%rip), %rsi")
    textLines.push("    mov $" + toString(len(op.text)) + ", %rdx")
    textLines.push("    syscall")
}

func escapeAsmString(string text) string {
    var out = ""
    var i = 0
    while i < len(text) {
        var ch = charAt(text, i)
        if ch == "\\" {
            out = out + "\\\\"
        } else if ch == "\"" {
            out = out + "\\\""
        } else if ch == "\n" {
            out = out + "\\n"
        } else if ch == "\t" {
            out = out + "\\t"
        } else if ch == "\r" {
            out = out + "\\r"
        } else {
            out = out + ch
        }
        i = i + 1
    }
    out
}

func copyBindings(Vec[Binding] source) Vec[Binding] {
    var out = Vec[Binding]()
    var i = 0
    while i < source.len() {
        out.push(source[i])
        i = i + 1
    }
    out
}

func findBindingIndex(Vec[Binding] env, string name) int32 {
    var i = env.len()
    while i > 0 {
        i = i - 1
        if env[i].name == name {
            return i
        }
    }
    -1
}

func propagateBindings(Vec[Binding] mut outer, Vec[Binding] inner) () {
    var i = 0
    while i < inner.len() {
        var index = findBindingIndex(outer, inner[i].name)
        if index >= 0 {
            outer.set(index, inner[i])
        }
        i = i + 1
    }
}

func joinLines(Vec[string] lines) string {
    joinWith(lines, "\n")
}

func joinWith(Vec[string] values, string sep) string {
    var out = ""
    var first = true
    var i = 0
    while i < values.len() {
        if !first {
            out = out + sep
        }
        out = out + values[i]
        first = false
        i = i + 1
    }
    out
}

func reportFailure(string message) int32 {
    eprintln("backend error: " + message)
    1
}
