from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import platform

BUILD_OUTPUT_ROOT = Path("/app/tmp")


@dataclass
class ArchInfo:
    name: str
    emitter: object | None = None


def detect_host_arch() -> str:
    machine = platform.machine().lower()
    mapping = {
        "x86_64": "amd64",
        "amd64": "amd64",
    }
    return mapping.get(machine, machine)
