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


def _copy_reg(target_reg: str) -> Selector:
    return lambda inst: [AsmInstruction("mov", (f"%{inst.source_reg}", f"%{target_reg}"))]


def _lea_symbol(target_reg: str) -> Selector:
    return lambda inst: [AsmInstruction("lea", (f"{inst.symbol}(%rip)", f"%{target_reg}"))]


def _add_i32(target_reg: str) -> Selector:
    return lambda inst: [AsmInstruction("add", (f"%{inst.source_reg}", f"%{target_reg}"))]


def _cmp_le_i32(_: LoweredInstruction) -> list[AsmInstruction]:
    return [AsmInstruction("cmp", (f"%{_.source_reg}", f"%{_.target_reg}"))]


def _branch_if(_: LoweredInstruction) -> list[AsmInstruction]:
    ops = [AsmInstruction("jle", (_.target_label,))]
    if _.false_label:
        ops.append(AsmInstruction("jmp", (_.false_label,)))
    return ops


def _label(_: LoweredInstruction) -> list[AsmInstruction]:
    return [AsmInstruction(f"{_.target_label}:")]


def _call_builtin(inst: LoweredInstruction) -> list[AsmInstruction]:
    if inst.builtin in {"syscall_write", "syscall_exit"}:
        return [AsmInstruction("syscall")]
    if inst.builtin == "print_i32":
        return []
    raise ValueError(f"unsupported amd64 builtin {inst.builtin}")


def _syscall(_: LoweredInstruction) -> list[AsmInstruction]:
    return [AsmInstruction("syscall")]


_SELECTORS: dict[tuple[str, str, str], Selector] = {
    ("load_const", "i64", "rax"): _mov_imm("rax"),
    ("load_const", "i64", "rdi"): _mov_imm("rdi"),
    ("load_const", "i64", "rdx"): _mov_imm("rdx"),
    ("load_const", "i64", "r8"): _mov_imm("r8"),
    ("load_const", "i64", "r9"): _mov_imm("r9"),
    ("load_const", "i64", "r11"): _mov_imm("r11"),
    ("copy_reg", "i64", "rax"): _copy_reg("rax"),
    ("copy_reg", "i64", "rdi"): _copy_reg("rdi"),
    ("copy_reg", "i64", "rdx"): _copy_reg("rdx"),
    ("copy_reg", "i64", "rcx"): _copy_reg("rcx"),
    ("copy_reg", "ptr", "rsi"): _copy_reg("rsi"),
    ("load_addr", "ptr", "rsi"): _lea_symbol("rsi"),
    ("load_addr", "ptr", "r10"): _lea_symbol("r10"),
    ("add_i32", "i32", "eax"): _add_i32("eax"),
    ("add_i32", "i32", "ecx"): _add_i32("ecx"),
    ("cmp_le_i32", "i32", ""): _cmp_le_i32,
    ("branch_if", "flags", ""): _branch_if,
    ("jump", "label", ""): lambda inst: [AsmInstruction("jmp", (inst.target_label,))],
    ("label", "label", ""): _label,
    ("call_builtin", "unit", ""): _call_builtin,
    ("syscall", "unit", ""): _syscall,
}
