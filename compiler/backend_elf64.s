package compiler.backend_elf64

use frontend.BlockExpr
use frontend.Expr
use frontend.FunctionDecl
use frontend.Item
use frontend.SourceFile
use std.option.Option
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
    // Phase 1 keeps compile-time execution intentionally narrow.
    // We will expand stmt/expr coverage as we move the Python backend logic over.
    body
    env
    ops
    Result::Ok(0)
}

func execute_stmt(
    frontend.Stmt stmt,
    Vec[LocalBinding] env,
    Vec[ProgramOp] ops,
) -> Result[(), BackendError] {
    stmt
    env
    ops
    Result::Err(unsupported("backend stmt"))
}

func eval_expr(
    Expr expr,
    Vec[LocalBinding] env,
) -> Result[Value, BackendError] {
    expr
    env
    Result::Err(unsupported("backend expr"))
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
    // Phase 1 host boundary:
    // - write temporary .s file
    // - call as
    // - call ld
    asm_text
    output_path
    Result::Err(BackendError {
        message: "host assembler/linker bridge not wired yet",
    })
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
    text
    "0"
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
