from __future__ import annotations

from dataclasses import dataclass


class Expr:
    pass


@dataclass(frozen=True)
class IntLiteral(Expr):
    value: int


@dataclass(frozen=True)
class StringExpr(Expr):
    value: str


@dataclass(frozen=True)
class BinaryExpr(Expr):
    left: Expr
    op: str
    right: Expr


@dataclass(frozen=True)
class NameExpr(Expr):
    name: str


@dataclass(frozen=True)
class RangeExpr(Expr):
    start: Expr
    end: Expr


class Stmt:
    pass


@dataclass(frozen=True)
class PrintlnStmt(Stmt):
    value: Expr


@dataclass(frozen=True)
class LetStmt(Stmt):
    name: str
    type_name: str | None
    value: Expr


@dataclass(frozen=True)
class AssignStmt(Stmt):
    name: str
    value: Expr


@dataclass(frozen=True)
class ForStmt(Stmt):
    init: Stmt
    condition: Expr
    step: Stmt
    body: list[Stmt]


@dataclass(frozen=True)
class FunctionDecl:
    name: str
    body: list[Stmt]


@dataclass(frozen=True)
class SourceFile:
    package: str
    functions: list[FunctionDecl]
