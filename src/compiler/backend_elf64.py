from __future__ import annotations

from dataclasses import dataclass
import os
import subprocess
import tempfile
from pathlib import path

from compiler.ast import sourcefile
from compiler.interpreter import interpreter, interpretererror

build_output_root = path(os.environ.get("s_build_output_root", "/tmp/s-build"))


class backenderror(exception):
    pass


@dataclass
class writeop:
    fd: int
    text: str


class recordinginterpreter(interpreter):
    def __init__(self, source: sourcefile) -> none:
        super().__init__(source)
        self.ops: list[writeop] = []

    def call_function(self, name: str, args: list[object]) -> object:
        if name == "println":
            self.ops.append(writeop(fd=1, text=("" if not args else self._stringify(args[0])) + "\n"))
            return none
        if name == "eprintln":
            self.ops.append(writeop(fd=2, text=("" if not args else self._stringify(args[0])) + "\n"))
            return none
        return super().call_function(name, args)


def build_executable(source: sourcefile, output_path: path) -> none:
    build_output_root.mkdir(parents=true, exist_ok=true)
    output_path.parent.mkdir(parents=true, exist_ok=true)
    program = _compile_program(source)
    asm = _emit_asm(program)

    with tempfile.temporarydirectory(prefix="s-build-", dir=str(build_output_root)) as tmp:
        workdir = path(tmp)
        asm_path = workdir / "out.s"
        obj_path = workdir / "out.o"
        asm_path.write_text(asm)

        try:
            subprocess.run(["as", "-o", str(obj_path), str(asm_path)], check=true)
            subprocess.run(["ld", "-o", str(output_path), str(obj_path)], check=true)
        except subprocess.calledprocesserror as exc:
            raise backenderror(f"toolchain failed with exit code {exc.returncode}") from exc


def _compile_program(source: sourcefile) -> tuple[list[writeop], int]:
    interpreter = recordinginterpreter(source)
    try:
        exit_code = interpreter.run_main()
    except interpretererror as exc:
        raise backenderror(str(exc)) from exc
    return interpreter.ops, int(exit_code)


def _emit_asm(program: tuple[list[writeop], int]) -> str:
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
