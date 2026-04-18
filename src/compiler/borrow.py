from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional

from compiler.ownership import ownershipdecision
from compiler.typesys import type


@dataclass
class borrowdiagnostic:
    message: str


@dataclass
class varstate:
    ty: type
    moved: bool = False
    shared_borrows: int = 0
    mut_borrowed: bool = False


def analyze_block(
    block,
    initial: Dict[str, varstate],
    ownership_plan: Optional[Dict[str, ownershipdecision]] = None,
) -> List[borrowdiagnostic]:
    _ = (block, initial, ownership_plan)
    return []
