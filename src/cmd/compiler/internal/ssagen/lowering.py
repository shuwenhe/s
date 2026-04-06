from __future__ import annotations

from dataclasses import dataclass

from compiler.internal.ir import MIROp, MIRProgram


@dataclass(frozen=True)
class LoweredData:
    label: str
    text: str


@dataclass(frozen=True)
class LoweredInstruction:
    op: str
    value_type: str
    target_reg: str
    value: str = ""
    source_reg: str = ""
    symbol: str = ""
    target_label: str = ""
    false_label: str = ""
    builtin: str = ""


@dataclass(frozen=True)
class LoweredProgram:
    entry_symbol: str
    data: list[LoweredData]
    instructions: list[LoweredInstruction]
    exit_code: int


def lower_program(mir: MIRProgram, arch_name: str) -> LoweredProgram:
    data: list[LoweredData] = []
    instructions: list[LoweredInstruction] = []
    reg_map: dict[str, str] = {}

    for op in mir.ops:
        instructions.extend(_lower_mir_op(op, reg_map))

    for index, write in enumerate(mir.writes):
        label = f"message_{index}"
        encoded_len = len(write.text.encode("utf-8"))
        data.append(LoweredData(label=label, text=write.text))
        instructions.extend(
            [
                LoweredInstruction(op="load_const", value_type="i64", target_reg="r8", value="1"),
                LoweredInstruction(op="copy_reg", value_type="i64", target_reg="rax", source_reg="r8"),
                LoweredInstruction(op="load_const", value_type="i64", target_reg="r9", value=str(write.fd)),
                LoweredInstruction(op="copy_reg", value_type="i64", target_reg="rdi", source_reg="r9"),
                LoweredInstruction(op="load_addr", value_type="ptr", target_reg="r10", symbol=label),
                LoweredInstruction(op="copy_reg", value_type="ptr", target_reg="rsi", source_reg="r10"),
                LoweredInstruction(op="load_const", value_type="i64", target_reg="r11", value=str(encoded_len)),
                LoweredInstruction(op="copy_reg", value_type="i64", target_reg="rdx", source_reg="r11"),
                LoweredInstruction(op="call_builtin", value_type="unit", target_reg="", builtin="syscall_write"),
            ]
        )

    instructions.extend(
        [
            LoweredInstruction(op="load_const", value_type="i64", target_reg="r8", value="60"),
            LoweredInstruction(op="copy_reg", value_type="i64", target_reg="rax", source_reg="r8"),
            LoweredInstruction(op="load_const", value_type="i64", target_reg="r9", value=str(mir.exit_code)),
            LoweredInstruction(op="copy_reg", value_type="i64", target_reg="rdi", source_reg="r9"),
            LoweredInstruction(op="call_builtin", value_type="unit", target_reg="", builtin="syscall_exit"),
        ]
    )

    return LoweredProgram(
        entry_symbol=_entry_symbol(arch_name),
        data=data,
        instructions=instructions,
        exit_code=mir.exit_code,
    )


def _lower_mir_op(op: MIROp, reg_map: dict[str, str]) -> list[LoweredInstruction]:
    if op.op == "label":
        return [LoweredInstruction(op="label", value_type="label", target_reg="", target_label=op.target_label)]
    if op.op == "jump":
        return [LoweredInstruction(op="jump", value_type="label", target_reg="", target_label=op.target_label)]
    if op.op == "branch_if":
        return [
            LoweredInstruction(
                op="branch_if",
                value_type="flags",
                target_reg="",
                target_label=op.target_label,
                false_label=op.false_label,
            )
        ]
    if op.op == "call_builtin":
        source_reg = _ensure_reg(op.target, reg_map)
        return [
            LoweredInstruction(
                op="call_builtin",
                value_type="unit",
                target_reg="",
                builtin=op.source,
                source_reg=source_reg,
            )
        ]

    target_reg = _ensure_reg(op.target, reg_map)
    if op.op == "load_const":
        return [LoweredInstruction(op="load_const", value_type="i32", target_reg=target_reg, value=str(op.value))]
    if op.op == "add_i32":
        return [
            LoweredInstruction(
                op="add_i32",
                value_type="i32",
                target_reg=target_reg,
                source_reg=_ensure_reg(op.source, reg_map),
            )
        ]
    if op.op == "cmp_le_i32":
        return [
            LoweredInstruction(
                op="cmp_le_i32",
                value_type="i32",
                target_reg=target_reg,
                source_reg=_ensure_reg(op.source, reg_map),
            )
        ]
    return []


def _ensure_reg(name: str, reg_map: dict[str, str]) -> str:
    if name in reg_map:
        return reg_map[name]
    pool = ["eax", "ecx", "edx", "r8d", "r9d", "r10d", "r11d"]
    reg = pool[len(reg_map) % len(pool)]
    reg_map[name] = reg
    return reg


def _entry_symbol(arch_name: str) -> str:
    if arch_name == "amd64":
        return "_start"
    return "_start"
