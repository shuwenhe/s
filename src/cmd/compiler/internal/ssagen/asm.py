from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess
import tempfile

from compiler.internal.base.config import BUILD_OUTPUT_ROOT


class BackendError(Exception):
    pass


@dataclass(frozen=True)
class AsmData:
    label: str
    text: str


@dataclass(frozen=True)
class AsmInstruction:
    opcode: str
    operands: tuple[str, ...] = ()


@dataclass(frozen=True)
class AsmProgram:
    entry_symbol: str
    data: list[AsmData]
    text: list[AsmInstruction]
    exit_code: int


def emit_program(program: AsmProgram, output_path: Path) -> None:
    BUILD_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    asm = render_program(program)

    with tempfile.TemporaryDirectory(prefix="s-build-", dir=str(BUILD_OUTPUT_ROOT)) as tmp:
        workdir = Path(tmp)
        asm_path = workdir / "out.s"
        obj_path = workdir / "out.o"
        asm_path.write_text(asm)

        try:
            subprocess.run(["as", "-o", str(obj_path), str(asm_path)], check=True)
            subprocess.run(["ld", "-o", str(output_path), str(obj_path)], check=True)
        except subprocess.CalledProcessError as exc:
            raise BackendError(f"toolchain failed with exit code {exc.returncode}") from exc


def render_program(program: AsmProgram) -> str:
    data_lines: list[str] = [".section .data"]
    text_lines: list[str] = [".section .text", f".global {program.entry_symbol}", f"{program.entry_symbol}:"]

    for data in program.data:
        encoded = data.text.encode("utf-8")
        payload = ", ".join(str(byte) for byte in encoded) if encoded else "0"
        data_lines.append(f"{data.label}:")
        data_lines.append(f"    .byte {payload}")

    for insn in program.text:
        if insn.operands:
            text_lines.append(f"    {insn.opcode} " + ", ".join(insn.operands))
        else:
            text_lines.append(f"    {insn.opcode}")

    text_lines.extend(
        [
            "    mov $60, %rax",
            f"    mov ${program.exit_code}, %rdi",
            "    syscall",
        ]
    )
    return "\n".join(data_lines + [""] + text_lines + [""])
