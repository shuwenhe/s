from __future__ import annotations

from pathlib import Path
from typing import Callable

from compiler.internal.ssagen.asm import AsmData, AsmInstruction, AsmProgram, emit_program
from compiler.internal.ssagen.lowering import LoweredInstruction, LoweredProgram

Selector = Callable[[LoweredInstruction], list[AsmInstruction]]


def arch_name() -> str:
    return "amd64"


def select_instructions(program: LoweredProgram) -> AsmProgram:
    data = [AsmData(label=item.label, text=item.text) for item in program.data]
    text: list[AsmInstruction] = []

    for inst in program.instructions:
        text.extend(_select_instruction(inst))

    return AsmProgram(
        entry_symbol=program.entry_symbol,
        data=data,
        text=text,
    )


def link_program(program: LoweredProgram, output_path: str | Path) -> None:
    emit_program(select_instructions(program), Path(output_path))


def _select_instruction(inst: LoweredInstruction) -> list[AsmInstruction]:
    selector = _SELECTORS.get((inst.op, inst.value_type, inst.target_reg))
    if selector is None:
        selector = _SELECTORS.get((inst.op, inst.value_type, ""))
    if selector is None:
        raise ValueError(
            f"amd64 selector missing for op={inst.op} type={inst.value_type} target={inst.target_reg}"
        )
    return selector(inst)


def _mov_imm(target_reg: str) -> Selector:
    return lambda inst: [AsmInstruction("mov", (f"${inst.value}", f"%{target_reg}"))]


def _lea_symbol(target_reg: str) -> Selector:
    return lambda inst: [AsmInstruction("lea", (f"{inst.symbol}(%rip)", f"%{target_reg}"))]


def _syscall(_: LoweredInstruction) -> list[AsmInstruction]:
    return [AsmInstruction("syscall")]


_SELECTORS: dict[tuple[str, str, str], Selector] = {
    ("load_syscall_nr", "syscall_no", "rax"): _mov_imm("rax"),
    ("load_fd", "fd", "rdi"): _mov_imm("rdi"),
    ("load_len", "size", "rdx"): _mov_imm("rdx"),
    ("load_exit_code", "exit_code", "rdi"): _mov_imm("rdi"),
    ("load_addr", "ptr", "rsi"): _lea_symbol("rsi"),
    ("syscall", "unit", ""): _syscall,
}
