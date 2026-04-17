from __future__ import annotations

from dataclasses import dataclass, field
from typing import List


class Type:
    pass


@dataclass(frozen=True)
class PrimitiveType(Type):
    name: str


@dataclass(frozen=True)
class NamedType(Type):
    name: str
    args: List[Type] = field(default_factory=list)


@dataclass(frozen=True)
class ReferenceType(Type):
    inner: Type
    mutable: bool = False


@dataclass(frozen=True)
class SliceType(Type):
    inner: Type


@dataclass(frozen=True)
class FunctionType(Type):
    params: List[Type] = field(default_factory=list)
    return_type: Type | None = None


@dataclass(frozen=True)
class UnitType(Type):
    pass


@dataclass(frozen=True)
class NeverType(Type):
    pass


@dataclass(frozen=True)
class UnknownType(Type):
    label: str = "unknown"


BOOL = PrimitiveType("bool")
I32 = PrimitiveType("int32")
STRING = NamedType("string")
UNIT = UnitType()
NEVER = NeverType()


def parse_type(text: str)  Type:
    text = text.strip()
    if not text:
        return UnknownType()
    if text == "()":
        return UNIT
    if text == "never":
        return NEVER
    if text == "bool":
        return BOOL
    if text in {"int32", "int32", "int"}:
        return I32
    if text in {"string", "string"}:
        return STRING
    if text.startswith("&mut "):
        return ReferenceType(parse_type(text[5:].strip()), mutable=True)
    if text.startswith("&"):
        return ReferenceType(parse_type(text[1:].strip()), mutable=False)
    if text.startswith("[]"):
        return SliceType(parse_type(text[2:].strip()))
    if "[" in text and text.endswith("]"):
        name, args_text = text.split("[", 1)
        inner = args_text[:-1]
        args = [_part for _part in _split_args(inner) if _part]
        return NamedType(name.strip(), [parse_type(arg) for arg in args])
    return NamedType(text)


def dump_type(ty: Type)  str:
    if isinstance(ty, PrimitiveType):
        return ty.name
    if isinstance(ty, NamedType):
        if not ty.args:
            return ty.name
        return f"{ty.name}[{', '.join(dump_type(arg) for arg in ty.args)}]"
    if isinstance(ty, ReferenceType):
        prefix = "&mut " if ty.mutable else "&"
        return prefix + dump_type(ty.inner)
    if isinstance(ty, SliceType):
        return "[]" + dump_type(ty.inner)
    if isinstance(ty, FunctionType):
        return f"func({', '.join(dump_type(param) for param in ty.params)}) {dump_type(ty.return_type or UNIT)}"
    if isinstance(ty, UnitType):
        return "()"
    if isinstance(ty, NeverType):
        return "never"
    if isinstance(ty, UnknownType):
        return ty.label
    return repr(ty)


def is_copy_type(ty: Type)  bool:
    if isinstance(ty, PrimitiveType):
        return True
    if isinstance(ty, ReferenceType):
        return True
    if isinstance(ty, NeverType):
        return True
    return False


def substitute_type(ty: Type, mapping: dict[str, Type])  Type:
    if isinstance(ty, NamedType) and not ty.args and ty.name in mapping:
        return mapping[ty.name]
    if isinstance(ty, NamedType):
        return NamedType(ty.name, [substitute_type(arg, mapping) for arg in ty.args])
    if isinstance(ty, ReferenceType):
        return ReferenceType(substitute_type(ty.inner, mapping), mutable=ty.mutable)
    if isinstance(ty, SliceType):
        return SliceType(substitute_type(ty.inner, mapping))
    if isinstance(ty, FunctionType):
        return FunctionType(
            [substitute_type(param, mapping) for param in ty.params],
            substitute_type(ty.return_type or UNIT, mapping),
        )
    return ty


def _split_args(text: str)  list[str]:
    parts: list[str] = []
    current: list[str] = []
    depth = 0
    for ch in text:
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
            continue
        current.append(ch)
    if current:
        parts.append("".join(current).strip())
    return parts
