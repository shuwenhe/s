from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple
import os
import subprocess
import tempfile

from compiler.ast import sourcefile
from compiler.interpreter import interpreter, interpretererror

build_output_root = Path(os.environ.get("s_build_output_root", "/tmp/s-build"))


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
    interpreter = recordinginterpreter(source)
    try:
        exit_code = interpreter.run_main()
    except interpretererror as exc:
        raise backenderror(str(exc)) from exc
    return interpreter.ops, int(exit_code)


def _emit_asm(program: Tuple[List[writeop], int]) -> str:
    ops, exit_code = program
    data_lines: List[str] = [".section .data"]
    text_lines: List[str] = [".section .text", ".global _start", "_start:"]

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
