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
    symbol: str = ""


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
                LoweredInstruction(op="mov_imm", value_type="i64", target_reg="rax", value="1"),
                LoweredInstruction(op="mov_imm", value_type="i64", target_reg="rdi", value=str(write.fd)),
                LoweredInstruction(op="lea_symbol", value_type="ptr", target_reg="rsi", symbol=label),
                LoweredInstruction(op="mov_imm", value_type="i64", target_reg="rdx", value=str(encoded_len)),
                LoweredInstruction(op="syscall", value_type="unit", target_reg=""),
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
