from __future__ import annotations

from compiler.internal.base.config import archinfo
from compiler.internal.ssagen import loweredprogram, build_executable
from .isel import arch_name, link_program, select_instructions


def init(info: archinfo) -> none:
    info.name = "amd64"
    info.emitter = build_executable


__all__ = ["init", "arch_name", "link_program", "select_instructions", "loweredprogram"]
