from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple
import os
import platform
import subprocess
import tempfile

from compiler.ast import callexpr, functiondecl, nameexpr, returnstmt, sourcefile
from compiler.interpreter import interpreter, interpretererror

build_output_root = Path(os.environ.get("s_build_output_root", "/tmp/s-build"))
bootstrap_base_compiler = os.environ.get("s_bootstrap_base_compiler", "/app/s/bin/s-native")


class backenderror(Exception):
    pass


@dataclass
class writeop:
    fd: int
    text: str


class recordinginterpreter(interpreter):
    def __init__(self, source: sourcefile) -> None:
        super().__init__(source)
        self.ops: List[writeop] = []

    def call_function(self, name: str, args: List[object]) -> object:
        if name == "println":
            self.ops.append(writeop(fd=1, text=("" if not args else self._stringify(args[0])) + "\n"))
            return None
        if name == "eprintln":
            self.ops.append(writeop(fd=2, text=("" if not args else self._stringify(args[0])) + "\n"))
            return None
        return super().call_function(name, args)


def build_executable(source: sourcefile, output_path: Path) -> None:
    build_output_root.mkdir(parents=True, exist_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if _is_compiler_runtime_entry(source):
        base_compiler = Path(bootstrap_base_compiler).resolve()
        if output_path.resolve() == base_compiler:
            raise backenderror(
                "refusing to generate a launcher that execs itself; set s_bootstrap_base_compiler to a different binary"
            )
        asm = _emit_runtime_launcher_asm(str(base_compiler))
    else:
        program = _compile_program(source)
        asm = _emit_asm(program)

    with tempfile.TemporaryDirectory(prefix="s-build-", dir=str(build_output_root)) as tmp:
        workdir = Path(tmp)
        asm_path = workdir / "out.s"
        obj_path = workdir / "out.o"
        asm_path.write_text(asm)

        try:
            subprocess.run(["as", "-o", str(obj_path), str(asm_path)], check=True)
            subprocess.run(["ld", "-o", str(output_path), str(obj_path)], check=True)
        except subprocess.CalledProcessError as exc:
            raise backenderror(f"toolchain failed with exit code {exc.returncode}") from exc


def _compile_program(source: sourcefile) -> Tuple[List[writeop], int]:
    runtime = recordinginterpreter(source)
    try:
        exit_code = runtime.run_main()
    except interpretererror as exc:
        raise backenderror(str(exc)) from exc
    return runtime.ops, int(exit_code)


def _is_compiler_runtime_entry(source: sourcefile) -> bool:
    has_compiler_import = any(use.path == "compile.internal.compiler.main" for use in source.uses)
    has_host_args_import = any(use.path == "std.env.args" for use in source.uses)
    if not has_compiler_import or not has_host_args_import:
        return False

    for item in source.items:
        if not isinstance(item, functiondecl):
            continue
        if item.sig.name != "main" or item.body is None:
            continue
        for statement in item.body.statements:
            if not isinstance(statement, returnstmt) or statement.value is None:
                continue
            value = statement.value
            if not isinstance(value, callexpr):
                continue
            if not isinstance(value.callee, nameexpr) or value.callee.name != "compiler_main":
                continue
            if len(value.args) != 1:
                continue
            arg = value.args[0]
            if not isinstance(arg, callexpr):
                continue
            if not isinstance(arg.callee, nameexpr) or arg.callee.name != "host_args":
                continue
            return True
    return False


def _host_arch() -> str:
    machine = platform.machine().lower()
    if machine in {"x86_64", "amd64"}:
        return "x86_64"
    if machine in {"aarch64", "arm64"}:
        return "aarch64"
    raise backenderror(f"unsupported host architecture: {machine}")


def _emit_runtime_launcher_asm(base_compiler_path: str) -> str:
    escaped_path = base_compiler_path.replace("\\", "\\\\").replace('"', '\\"')
    arch = _host_arch()

    if arch == "aarch64":
        lines = [
            ".section .rodata",
            "base_compiler_path:",
            f'    .asciz "{escaped_path}"',
            "",
            ".section .text",
            ".global _start",
            "_start:",
            "    ldr x9, [sp]",  # argc
            "    add x1, sp, #8",  # argv
            "    add x2, x1, x9, lsl #3",  # argv + argc*8
            "    add x2, x2, #8",  # envp = argv + (argc+1)*8
            "    adrp x0, base_compiler_path",
            "    add x0, x0, :lo12:base_compiler_path",
            "    mov x8, #221",  # execve
            "    svc #0",
            "",
            "    mov x0, #127",  # exit on execve failure
            "    mov x8, #93",
            "    svc #0",
            "",
        ]
        return "\n".join(lines)

    if arch == "x86_64":
        lines = [
            ".section .rodata",
            "base_compiler_path:",
            f'    .asciz "{escaped_path}"',
            "",
            ".section .text",
            ".global _start",
            "_start:",
            "    mov (%rsp), %rcx",  # argc
            "    lea 8(%rsp), %r8",  # argv
            "    lea 16(%rsp,%rcx,8), %rdx",  # envp
            "    lea base_compiler_path(%rip), %rdi",
            "    mov %r8, %rsi",
            "    mov $59, %rax",  # execve
            "    syscall",
            "",
            "    mov $60, %rax",  # exit on execve failure
            "    mov $127, %rdi",
            "    syscall",
            "",
        ]
        return "\n".join(lines)

    raise backenderror("unsupported architecture for runtime launcher")


def _emit_asm(program: Tuple[List[writeop], int]) -> str:
    ops, exit_code = program
    arch = _host_arch()

    data_lines: List[str] = [".section .data"]
    text_lines: List[str] = [".section .text", ".global _start", "_start:"]

    for index, op in enumerate(ops):
        label = f"message_{index}"
        encoded = op.text.encode("utf-8")
        payload = ", ".join(str(byte) for byte in encoded) if encoded else "0"

        data_lines.append(f"{label}:")
        data_lines.append(f"    .byte {payload}")

        if arch == "aarch64":
            text_lines.extend(
                [
                    f"    mov x0, #{op.fd}",
                    f"    adrp x1, {label}",
                    f"    add x1, x1, :lo12:{label}",
                    f"    mov x2, #{len(encoded)}",
                    "    mov x8, #64",
                    "    svc #0",
                ]
            )
        elif arch == "x86_64":
            text_lines.extend(
                [
                    "    mov $1, %rax",
                    f"    mov ${op.fd}, %rdi",
                    f"    lea {label}(%rip), %rsi",
                    f"    mov ${len(encoded)}, %rdx",
                    "    syscall",
                ]
            )
        else:
            raise backenderror("unsupported architecture for write op")

    if arch == "aarch64":
        text_lines.extend(
            [
                f"    mov x0, #{exit_code}",
                "    mov x8, #93",
                "    svc #0",
            ]
        )
    elif arch == "x86_64":
        text_lines.extend(
            [
                "    mov $60, %rax",
                f"    mov ${exit_code}, %rdi",
                "    syscall",
            ]
        )
    else:
        raise backenderror("unsupported architecture for program emission")

    return "\n".join(data_lines + [""] + text_lines + [""])
