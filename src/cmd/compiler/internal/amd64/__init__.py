from __future__ import annotations

from pathlib import Path

from compiler.backend_elf64 import emit_program
from compiler.internal.base.config import ArchInfo
from compiler.internal.ssagen import MachineProgram, build_executable


def Init(info: ArchInfo) -> None:
    info.name = "amd64"
    info.emitter = build_executable


def arch_name() -> str:
    return "amd64"


def link_program(program: MachineProgram, output_path: str | Path) -> None:
    emit_program(program, Path(output_path))
