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
                LoweredInstruction(op="load_syscall_nr", value_type="syscall_no", target_reg="rax", value="1"),
                LoweredInstruction(op="load_fd", value_type="fd", target_reg="rdi", value=str(write.fd)),
                LoweredInstruction(op="load_addr", value_type="ptr", target_reg="rsi", symbol=label),
                LoweredInstruction(op="load_len", value_type="size", target_reg="rdx", value=str(encoded_len)),
                LoweredInstruction(op="syscall", value_type="unit", target_reg=""),
            ]
        )

    instructions.extend(
        [
            LoweredInstruction(op="load_syscall_nr", value_type="syscall_no", target_reg="rax", value="60"),
            LoweredInstruction(op="load_exit_code", value_type="exit_code", target_reg="rdi", value=str(mir.exit_code)),
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
