from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess
import tempfile

from compiler.ast import SourceFile
from compiler.interpreter import Interpreter, InterpreterError


class BackendError(Exception):
    pass


@dataclass
class WriteOp:
    fd: int
    text: str


class RecordingInterpreter(Interpreter):
    def __init__(self, source: SourceFile) -> None:
        super().__init__(source)
        self.ops: list[WriteOp] = []

    def call_function(self, name: str, args: list[object]) -> object:
        if name == "println":
            self.ops.append(WriteOp(fd=1, text=("" if not args else self._stringify(args[0])) + "\n"))
            return None
        if name == "eprintln":
            self.ops.append(WriteOp(fd=2, text=("" if not args else self._stringify(args[0])) + "\n"))
            return None
        return super().call_function(name, args)


def build_executable(source: SourceFile, output_path: Path) -> None:
    if source.package == "runtime.runner":
        _build_native_runner(output_path)
        return
    program = _compile_program(source)
    asm = _emit_asm(program)

    with tempfile.TemporaryDirectory(prefix="s-build-") as tmp:
        workdir = Path(tmp)
        asm_path = workdir / "out.s"
        obj_path = workdir / "out.o"
        asm_path.write_text(asm)

        try:
            subprocess.run(["as", "-o", str(obj_path), str(asm_path)], check=True)
            subprocess.run(["ld", "-o", str(output_path), str(obj_path)], check=True)
        except subprocess.CalledProcessError as exc:
            raise BackendError(f"toolchain failed with exit code {exc.returncode}") from exc


def _build_native_runner(output_path: Path) -> None:
    template = Path("/app/s/runtime/runner_native_template.c").resolve()
    try:
        subprocess.run(
            ["cc", "-O2", "-std=c11", str(template), "-o", str(output_path)],
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise BackendError(f"native runner bootstrap failed with exit code {exc.returncode}") from exc


def _compile_program(source: SourceFile) -> tuple[list[WriteOp], int]:
    interpreter = RecordingInterpreter(source)
    try:
        exit_code = interpreter.run_main()
    except InterpreterError as exc:
        raise BackendError(str(exc)) from exc
    return interpreter.ops, int(exit_code)


def _emit_asm(program: tuple[list[WriteOp], int]) -> str:
    ops, exit_code = program
    data_lines: list[str] = [".section .data"]
    text_lines: list[str] = [".section .text", ".global _start", "_start:"]

    for index, op in enumerate(ops):
        label = f"message_{index}"
        encoded = op.text.encode("utf-8")
        payload = ", ".join(str(byte) for byte in encoded) if encoded else "0"
        data_lines.append(f"{label}:")
        data_lines.append(f"    .byte {payload}")
        text_lines.extend(
            [
                "    mov $1, %rax",
                f"    mov ${op.fd}, %rdi",
                f"    lea {label}(%rip), %rsi",
                f"    mov ${len(encoded)}, %rdx",
                "    syscall",
            ]
        )

    text_lines.extend(
        [
            "    mov $60, %rax",
            f"    mov ${exit_code}, %rdi",
            "    syscall",
        ]
    )
    return "\n".join(data_lines + [""] + text_lines + [""])
