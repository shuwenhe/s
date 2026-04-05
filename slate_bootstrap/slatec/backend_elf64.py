from __future__ import annotations

from pathlib import Path
import subprocess

from slatec.ast import (
    AssignStmt,
    BinaryExpr,
    ForStmt,
    FunctionDecl,
    IntLiteral,
    LetStmt,
    NameExpr,
    PrintlnStmt,
    SourceFile,
    StringExpr,
)


class BackendError(Exception):
    pass


def build_executable(source: SourceFile, output_path: Path, workdir: Path) -> None:
    main_fn = next(fn for fn in source.functions if fn.name == "main")
    parts = _execute_function(main_fn)
    message = "\n".join(parts) + ("\n" if parts else "")
    asm = _emit_asm(message)

    asm_path = workdir / "out.s"
    obj_path = workdir / "out.o"
    asm_path.write_text(asm)

    try:
        subprocess.run(["as", "-o", str(obj_path), str(asm_path)], check=True)
        subprocess.run(["ld", "-o", str(output_path), str(obj_path)], check=True)
    except subprocess.CalledProcessError as exc:
        raise BackendError(f"toolchain failed with exit code {exc.returncode}") from exc


def _emit_asm(message: str) -> str:
    encoded = message.encode("utf-8")
    payload = ", ".join(str(byte) for byte in encoded) if encoded else "0"
    size = len(encoded)
    return f""".global _start

.section .data
message:
    .byte {payload}

.section .text
_start:
    mov $1, %rax
    mov $1, %rdi
    lea message(%rip), %rsi
    mov ${size}, %rdx
    syscall

    mov $60, %rax
    xor %rdi, %rdi
    syscall
"""


def _execute_function(fn: FunctionDecl) -> list[str]:
    env: dict[str, int | str] = {}
    output: list[str] = []
    for stmt in fn.body:
        _execute_stmt(stmt, env, output)
    return output


def _execute_stmt(stmt, env: dict[str, int | str], output: list[str]) -> None:
    if isinstance(stmt, PrintlnStmt):
        output.append(_eval_expr(stmt.value, env))
        return
    if isinstance(stmt, LetStmt):
        env[stmt.name] = _eval_value(stmt.value, env)
        return
    if isinstance(stmt, AssignStmt):
        env[stmt.name] = _eval_value(stmt.value, env)
        return
    if isinstance(stmt, ForStmt):
        _execute_stmt(stmt.init, env, output)
        while _eval_bool(stmt.condition, env):
            for item in stmt.body:
                _execute_stmt(item, env, output)
            _execute_stmt(stmt.step, env, output)
        return
    raise BackendError("unsupported statement")


def _eval_expr(expr, env: dict[str, int | str]) -> str:
    value = _eval_value(expr, env)
    return str(value)


def _eval_value(expr, env: dict[str, int | str]) -> int | str:
    if isinstance(expr, StringExpr):
        return expr.value
    if isinstance(expr, IntLiteral):
        return expr.value
    if isinstance(expr, NameExpr):
        if expr.name not in env:
            raise BackendError(f"undefined name {expr.name}")
        return env[expr.name]
    if isinstance(expr, BinaryExpr):
        if expr.op == "+":
            return _eval_int(expr.left, env) + _eval_int(expr.right, env)
        if expr.op == "<=":
            return _eval_int(expr.left, env) <= _eval_int(expr.right, env)
        raise BackendError(f"unsupported operator {expr.op}")
    raise BackendError("unsupported expression")


def _eval_int(expr, env: dict[str, int | str]) -> int:
    value = _eval_value(expr, env)
    if not isinstance(value, int):
        raise BackendError("expected integer expression")
    return value


def _eval_bool(expr, env: dict[str, int | str]) -> bool:
    value = _eval_value(expr, env)
    if not isinstance(value, bool):
        raise BackendError("expected boolean expression")
    return value
