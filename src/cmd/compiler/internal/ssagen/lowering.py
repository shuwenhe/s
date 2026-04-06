from __future__ import annotations

from dataclasses import dataclass

from compiler.internal.ir import MIRProgram, MIRWriteOp


@dataclass(frozen=True)
class LoweredWriteOp:
    fd: int
    text: str


@dataclass(frozen=True)
class LoweredProgram:
    entry_symbol: str
    writes: list[LoweredWriteOp]
    exit_code: int


def lower_program(mir: MIRProgram, arch_name: str) -> LoweredProgram:
    return LoweredProgram(
        entry_symbol=_entry_symbol(arch_name),
        writes=[LoweredWriteOp(fd=write.fd, text=write.text) for write in mir.writes],
        exit_code=mir.exit_code,
    )


def _entry_symbol(arch_name: str) -> str:
    if arch_name == "amd64":
        return "_start"
    return "_start"
