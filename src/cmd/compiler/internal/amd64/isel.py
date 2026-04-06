from __future__ import annotations

from pathlib import Path

from compiler.internal.ssagen.asm import AsmData, AsmInstruction, AsmProgram, emit_program
from compiler.internal.ssagen.lowering import LoweredProgram


def arch_name() -> str:
    return "amd64"


def select_instructions(program: LoweredProgram) -> AsmProgram:
    data: list[AsmData] = []
    text: list[AsmInstruction] = []

    for index, write in enumerate(program.writes):
        label = f"message_{index}"
        data.append(AsmData(label=label, text=write.text))
        text.extend(
            [
                AsmInstruction("mov", ("$1", "%rax")),
                AsmInstruction("mov", (f"${write.fd}", "%rdi")),
                AsmInstruction("lea", (f"{label}(%rip)", "%rsi")),
                AsmInstruction("mov", (f"${len(write.text.encode('utf-8'))}", "%rdx")),
                AsmInstruction("syscall"),
            ]
        )

    return AsmProgram(
        entry_symbol=program.entry_symbol,
        data=data,
        text=text,
        exit_code=program.exit_code,
    )


def link_program(program: LoweredProgram, output_path: str | Path) -> None:
    emit_program(select_instructions(program), Path(output_path))
