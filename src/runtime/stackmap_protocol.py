from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class stackmaprecord:
    version: int
    arch: str
    functions: int


@dataclass(frozen=True)
class stackmapfunction:
    name: str
    slots: int
    bitmap: str
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

    version = int(fields.get("version", "1"))
    functions = int(fields.get("functions", "0"))
    return stackmaprecord(version=version, arch=arch, functions=functions)


def parse_stackmap_function_line(line: str) -> stackmapfunction:
    if not line.startswith("fn "):
        raise ValueError("stackmap function line must start with 'fn '")

    tokens = line.split()
    if len(tokens) < 2:
        raise ValueError("stackmap function line missing function name")

    name = tokens[1]
    fields = {}
    for token in tokens[2:]:
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        fields[key] = value

    slots = int(fields.get("slots", "0"))
    bitmap = fields.get("bitmap", "")
    callee_saved = int(fields.get("callee_saved", "0"))
    if bitmap == "":
        raise ValueError("stackmap function line missing bitmap")
    if slots > 0 and len(bitmap) != slots:
        raise ValueError("stackmap bitmap length must match slots")
    return stackmapfunction(name=name, slots=slots, bitmap=bitmap, callee_saved=callee_saved)


def parse_stackmap_text(text: str) -> tuple[stackmaprecord, list[stackmapfunction]]:
    lines = [line.strip() for line in text.splitlines() if line.strip() != ""]
    if len(lines) == 0:
        raise ValueError("empty stackmap text")

    header = parse_stackmap_header(lines[0])
    functions: list[stackmapfunction] = []
    for line in lines[1:]:
        if line.startswith("fn "):
            functions.append(parse_stackmap_function_line(line))

    if header.functions != 0 and len(functions) != header.functions:
        raise ValueError("stackmap function count does not match header")

    return header, functions
