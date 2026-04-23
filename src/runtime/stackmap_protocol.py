from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class stackmaprecord:
    arch: str
    spill_slots: int
    callee_saved: int


def parse_stackmap_header(line: str) -> stackmaprecord:
    if not line.startswith("stackmap "):
        raise ValueError("stackmap header must start with 'stackmap '")

    fields = {}
    for token in line.split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        fields[key] = value

    arch = fields.get("arch", "")
    if arch == "":
        raise ValueError("stackmap header missing arch")

    spill_slots = int(fields.get("spill_slots", "0"))
    callee_saved = int(fields.get("callee_saved", "0"))
    return stackmaprecord(arch=arch, spill_slots=spill_slots, callee_saved=callee_saved)
