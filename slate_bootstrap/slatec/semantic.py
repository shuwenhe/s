from __future__ import annotations

from slatec.ast import (
    AssignStmt,
    BinaryExpr,
    ForStmt,
    FunctionDecl,
    IntLiteral,
    LetStmt,
    NameExpr,
    PrintlnStmt,
    SourceFile,
    StringExpr,
)


class SemanticError(Exception):
    pass


def check(source: SourceFile) -> None:
    if source.package != "main":
        raise SemanticError("hello-world MVP requires `package main`")

    mains = [fn for fn in source.functions if fn.name == "main"]
    if not mains:
        raise SemanticError("entry function `main` not found")
    if len(mains) > 1:
        raise SemanticError("multiple `main` functions found")

    for fn in source.functions:
        _check_function(fn)


def _check_function(fn: FunctionDecl) -> None:
    env: set[str] = set()
    for stmt in fn.body:
        _check_stmt(stmt, env)

def _check_stmt(stmt, env: set[str]) -> None:
    if isinstance(stmt, PrintlnStmt):
        _check_expr(stmt.value, env)
        return
    if isinstance(stmt, LetStmt):
        _check_expr(stmt.value, env)
        env.add(stmt.name)
        return
    if isinstance(stmt, AssignStmt):
        if stmt.name not in env:
            raise SemanticError(f"assignment to undefined name {stmt.name}")
        _check_expr(stmt.value, env)
        return
    if isinstance(stmt, ForStmt):
        loop_env = set(env)
        _check_stmt(stmt.init, loop_env)
        cond_type = _check_expr(stmt.condition, loop_env)
        if cond_type != "bool":
            raise SemanticError("for condition must be boolean")
        _check_stmt(stmt.step, loop_env)
        body_env = set(loop_env)
        for item in stmt.body:
            _check_stmt(item, body_env)
        return
    raise SemanticError("unsupported statement")


def _check_expr(expr, env: set[str]) -> str:
    if isinstance(expr, IntLiteral):
        return "int"
    if isinstance(expr, StringExpr):
        return "string"
    if isinstance(expr, NameExpr):
        if expr.name not in env:
            raise SemanticError(f"undefined name {expr.name}")
        return "int"
    if isinstance(expr, BinaryExpr):
        left = _check_expr(expr.left, env)
        right = _check_expr(expr.right, env)
        if expr.op == "+":
            if left != "int" or right != "int":
                raise SemanticError("only integer addition is supported in MVP")
            return "int"
        if expr.op == "<=":
            if left != "int" or right != "int":
                raise SemanticError("only integer comparison is supported in MVP")
            return "bool"
        raise SemanticError(f"unsupported operator {expr.op}")
    raise SemanticError("unsupported expression")
