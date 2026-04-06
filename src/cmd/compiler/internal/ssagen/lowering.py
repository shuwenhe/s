from __future__ import annotations

from dataclasses import dataclass

from compiler.internal.ir import MIRProgram


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


def _entry_symbol(arch_name: str) -> str:
    if arch_name == "amd64":
        return "_start"
    return "_start"
