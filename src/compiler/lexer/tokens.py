from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto
from typing import List


class tokenkind(Enum):
    ident = auto()
    int = auto()
    string = auto()
    keyword = auto()
    symbol = auto()
    eof = auto()


keywords ={
"package",
"use",
"as",
"pub",
"func",
"let",
"var",
"const",
"static",
"struct",
"enum",
"trait",
"impl",
"for",
"if",
"else",
"while",
"switch",
"case",
"default",
"return",
"break",
"continue",
"true",
"false",
"nil",
"unsafe",
"extern",
"mut",
"where",
"in",
}


@dataclass(frozen=True)
class token:
    kind: tokenkind
    value: str
    line: int
    column: int


def dump_tokens(tokens: List[token]) -> str:
    return "\n".join(f"{token.line}:{token.column} {token.kind.name} {token.value}" for token in tokens)
