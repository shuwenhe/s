package compiler.backend_elf64

use frontend.BlockExpr
use frontend.CallExpr
use frontend.Expr
use frontend.ExprStmt
use frontend.FunctionDecl
use frontend.IntExpr
use frontend.Item
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
    exit_code: int,
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

func build_executable(SourceFile source, String output_path) -> Result[(), BackendError] {
    // Minimal backend design:
    // 1. compile SourceFile -> linear ProgramOp list
    // 2. emit Linux x86_64 assembly text
    // 3. invoke host as/ld through runtime boundary
    //
    // See /app/s/docs/backend_elf64.md for the executable MVP plan.
    //
    // The runnable algorithm still lives in backend_elf64.py today.
    var program = compile_program(source)?
    var asm_text = emit_asm(program)
    assemble_and_link(asm_text, output_path)
}

func compile_program(SourceFile source) -> Result[Program, BackendError] {
    var main_func = find_main(source)?
    var env = Vec[LocalBinding]()
    var ops = Vec[ProgramOp]()
    var exit_code = execute_function(main_func, env, ops)?
    ops.push(ProgramOp::Exit(ExitOp {
        code: exit_code,
    }))
    Result::Ok(Program {
        ops: ops,
        exit_code: exit_code,
    })
}

func emit_asm(Program program) -> String {
    emit_data_section(program.ops) + "\n" + emit_text_section(program.ops, program.exit_code) + "\n"
}

func find_main(SourceFile source) -> Result[FunctionDecl, BackendError] {
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

func execute_function(
    FunctionDecl func,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[int, BackendError] {
    match func.body {
        Option::Some(body) => execute_block(body, env, ops),
        Option::None => Result::Ok(0),
    }
}

func execute_block(
    BlockExpr body,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[int, BackendError] {
    for stmt in body.statements {
        match stmt {
            Stmt::Return(value) => return execute_return_stmt(value, env),
            _ => execute_stmt(stmt, env, ops)?,
        }
    }
    match body.final_expr {
        Option::Some(expr) => as_exit_code(eval_expr(expr, env)?),
        Option::None => Result::Ok(0),
    }
}

func execute_stmt(
    Stmt stmt,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[(), BackendError] {
    match stmt {
        Stmt::Var(value) => execute_var_stmt(value, env),
        Stmt::Expr(value) => execute_expr_stmt(value, env, ops),
        Stmt::Return(value) => {
            value
            Result::Ok(())
        }
    }
}

func eval_expr(
    Expr expr,
    Vec[LocalBinding] env,
) -> Result[Value, BackendError] {
    match expr {
        Expr::Int(value) => Result::Ok(Value::Int(parse_int_literal(value))),
        Expr::String(value) => Result::Ok(Value::String(unquote_string(value))),
        Expr::Bool(value) => Result::Ok(Value::Bool(value.value)),
        Expr::Name(value) => lookup_binding(env, value.name),
        Expr::Binary(value) => eval_binary_expr(value, env),
        _ => Result::Err(unsupported("backend expr")),
    }
}

func emit_data_section(Vec[ProgramOp] ops) -> String {
    var lines = Vec[String]()
    lines.push(".section .data")
    var index = 0
    for op in ops {
        match op {
            ProgramOp::WriteStdout(write) => append_data_payload(lines, "message_" + to_string(index), write.text),
            ProgramOp::WriteStderr(write) => append_data_payload(lines, "message_" + to_string(index), write.text),
            ProgramOp::Exit(_) => (),
        }
        index = index + 1
    }
    join_lines(lines)
}

func emit_text_section(Vec[ProgramOp] ops, int exit_code) -> String {
    var lines = Vec[String]()
    lines.push(".section .text")
    lines.push(".global _start")
    lines.push("_start:")
    var index = 0
    for op in ops {
        match op {
            ProgramOp::WriteStdout(write) => append_write_syscall(lines, 1, "message_" + to_string(index), write.text),
            ProgramOp::WriteStderr(write) => append_write_syscall(lines, 2, "message_" + to_string(index), write.text),
            ProgramOp::Exit(_) => (),
        }
        index = index + 1
    }
    lines.push("    mov $60, %rax")
    lines.push("    mov $" + to_string(exit_code) + ", %rdi")
    lines.push("    syscall")
    join_lines(lines)
}

func assemble_and_link(String asm_text, String output_path) -> Result[(), BackendError] {
    var temp_dir = host_make_temp_dir("s-build-")?
    var asm_path = temp_dir + "/out.s"
    var obj_path = temp_dir + "/out.o"
    host_write_text_file(asm_path, asm_text)?
    host_run_process(Vec[String] { "as", "-o", obj_path, asm_path })?
    host_run_process(Vec[String] { "ld", "-o", output_path, obj_path })?
    Result::Ok(())
}

func append_data_payload(Vec[String] lines, String label, String text) -> () {
    lines.push(label + ":")
    lines.push("    .byte " + encode_bytes(text))
}

func append_write_syscall(Vec[String] lines, int fd, String label, String text) -> () {
    lines.push("    mov $1, %rax")
    lines.push("    mov $" + to_string(fd) + ", %rdi")
    lines.push("    lea " + label + "(%rip), %rsi")
    lines.push("    mov $" + byte_len(text) + ", %rdx")
    lines.push("    syscall")
}

func encode_bytes(String text) -> String {
    __host_encode_bytes(text)
}

func byte_len(String text) -> String {
    // MVP: assume ASCII payloads first.
    to_string(text.len())
}

func join_lines(Vec[String] lines) -> String {
    var text = ""
    var index = 0
    while index < lines.len() {
        if index > 0 {
            text = text + "\n"
        }
        text = text + lines[index]
        index = index + 1
    }
    text
}

func unsupported(String feature) -> BackendError {
    BackendError {
        message: "unsupported " + feature,
    }
}

func execute_var_stmt(
    VarStmt stmt,
    Vec[LocalBinding] env,
) -> Result[(), BackendError] {
    var value = eval_expr(stmt.value, env)?
    bind_local(env, stmt.name, value)
    Result::Ok(())
}

func execute_expr_stmt(
    ExprStmt stmt,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[(), BackendError] {
    match stmt.expr {
        Expr::Call(value) => execute_call_stmt(value, env, ops),
        // Assignment, i++, and C-style for are part of the MVP backend target,
        // but they still need matching frontend AST nodes in /app/s/frontend.
        _ => {
            eval_expr(stmt.expr, env)?
            Result::Ok(())
        }
    }
}

func execute_call_stmt(
    CallExpr call,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[(), BackendError] {
    var callee_name = extract_callee_name(call)?
    if len(call.args) != 1 {
        return Result::Err(unsupported("call arity"))
    }
    var value = eval_expr(call.args[0], env)?
    var text = value_to_string(value)?

    if callee_name == "println" {
        ops.push(ProgramOp::WriteStdout(WriteOp {
            fd: 1,
            text: text + "\n",
        }))
        return Result::Ok(())
    }
    if callee_name == "eprintln" {
        ops.push(ProgramOp::WriteStderr(WriteOp {
            fd: 2,
            text: text + "\n",
        }))
        return Result::Ok(())
    }
    Result::Err(unsupported("call " + callee_name))
}

func execute_return_stmt(
    ReturnStmt stmt,
    Vec[LocalBinding] env,
) -> Result[int, BackendError] {
    match stmt.value {
        Option::Some(expr) => as_exit_code(eval_expr(expr, env)?),
        Option::None => Result::Ok(0),
    }
}

func eval_binary_expr(
    frontend.BinaryExpr expr,
    Vec[LocalBinding] env,
) -> Result[Value, BackendError] {
    var left = eval_expr(expr.left.value, env)?
    var right = eval_expr(expr.right.value, env)?

    if expr.op == "+" {
        match left {
            Value::Int(left_value) => {
                match right {
                    Value::Int(right_value) => return Result::Ok(Value::Int(left_value + right_value)),
                    _ => return Result::Err(unsupported("mixed + operands")),
                }
            }
            Value::String(left_value) => {
                match right {
                    Value::String(right_value) => return Result::Ok(Value::String(left_value + right_value)),
                    _ => return Result::Err(unsupported("mixed + operands")),
                }
            }
            _ => return Result::Err(unsupported("operator +")),
        }
    }

    if expr.op == "<=" {
        match left {
            Value::Int(left_value) => {
                match right {
                    Value::Int(right_value) => return Result::Ok(Value::Bool(left_value <= right_value)),
                    _ => return Result::Err(unsupported("operator <=")),
                }
            }
            _ => return Result::Err(unsupported("operator <=")),
        }
    }

    Result::Err(unsupported("binary operator " + expr.op))
}

func lookup_binding(
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

func bind_local(
    Vec[LocalBinding] env,
    String name,
    Value value,
) -> () {
    env.push(LocalBinding {
        name: name,
        value: value,
    })
}

func extract_callee_name(CallExpr call) -> Result[String, BackendError] {
    match call.callee.value {
        Expr::Name(value) => Result::Ok(value.name),
        _ => Result::Err(unsupported("callee")),
    }
}

func value_to_string(Value value) -> Result[String, BackendError] {
    match value {
        Value::Int(number) => Result::Ok(to_string(number)),
        Value::String(text) => Result::Ok(text),
        Value::Bool(flag) => Result::Ok(if flag { "true" } else { "false" }),
        Value::Unit(()) => Result::Ok("()"),
    }
}

func as_exit_code(Value value) -> Result[int, BackendError] {
    match value {
        Value::Int(number) => Result::Ok(number),
        Value::Bool(flag) => Result::Ok(if flag { 1 } else { 0 }),
        Value::Unit(()) => Result::Ok(0),
        _ => Result::Err(unsupported("main return type")),
    }
}

func parse_int_literal(IntExpr expr) -> int {
    parse_decimal(expr.value)
}

func unquote_string(StringExpr expr) -> String {
    var text = expr.value
    if len(text) < 2 {
        return text
    }
    slice(text, 1, len(text) - 1)
}

func host_write_text_file(String path, String contents) -> Result[(), BackendError] {
    match __host_write_text_file(path, contents) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => Result::Err(BackendError {
            message: err.message,
        }),
    }
}

func host_run_process(Vec[String] argv) -> Result[(), BackendError] {
    match __host_run_process(argv) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => Result::Err(BackendError {
            message: err.message,
        }),
    }
}

func host_make_temp_dir(String prefix) -> Result[String, BackendError] {
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

extern "intrinsic" func __host_encode_bytes(String text) -> String

func parse_decimal(String text) -> int {
    var value = 0
    var index = 0
    while index < len(text) {
        var ch = char_at(text, index)
        if ch == "_" {
            index = index + 1
            continue
        }
        value = value * 10 + digit_value(ch)
        index = index + 1
    }
    value
}

func digit_value(String ch) -> int {
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
