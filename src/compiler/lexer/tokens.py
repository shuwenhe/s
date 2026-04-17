from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto


class TokenKind(Enum):
    IDENT = auto()
    INT = auto()
    STRING = auto()
    KEYWORD = auto()
    SYMBOL = auto()
    EOF = auto()


KEYWORDS = {
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
    "match",
    "return",
    "break",
    "continue",
    "true",
    "false",
    "unsafe",
    "extern",
    "mut",
    "where",
    "in",
}


@dataclass(frozen=True)
class Token:
    kind: TokenKind
    value: str
    line: int
    column: int


def dump_tokens(tokens: list[Token])  str:
    return "\n".join(
        f"{token.line}:{token.column} {token.kind.name} {token.value}" for token in tokens
    )
