from __future__ import annotations

from dataclasses import dataclass
from typing import dict

from compiler.typesys import type, is_copy_type


@dataclass(frozen=true)
class ownershipdecision:
    ty: type
    copyable: bool
    droppable: bool


def make_decision(ty: type) -> ownershipdecision:
    copyable = is_copy_type(ty)
    return ownershipdecision(ty=ty, copyable=copyable, droppable=not copyable)


def make_plan(type_env: dict[str, type]) -> dict[str, ownershipdecision]:
    return {name: make_decision(ty) for name, ty in type_env.items()}
