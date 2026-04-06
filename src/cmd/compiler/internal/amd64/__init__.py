from __future__ import annotations

from compiler.internal.base.config import ArchInfo
from compiler.internal.ssagen import build_executable


def Init(info: ArchInfo) -> None:
    info.name = "amd64"
    info.emitter = build_executable
