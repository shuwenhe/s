from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from compiler.ast import (
    AssignStmt,
    BinaryExpr,
    BlockExpr,
    BoolExpr,
    CForStmt,
    CallExpr,
    Expr,
    ExprStmt,
    FunctionDecl,
    IfExpr,
    IncrementStmt,
    IntExpr,
    LetStmt,
    NameExpr,
    ReturnStmt,
    SourceFile,
    StringExpr,
)


class InterpreterError(Exception):
    pass


@dataclass
class ReturnSignal(Exception):
    value: Any


class Interpreter:
    def __init__(self, source: SourceFile) -> None:
        self.source = source
        self.functions = {
            item.sig.name: item
            for item in source.items
            if isinstance(item, FunctionDecl) and item.body is not None
        }

    def run_main(self) -> int:
        if "main" in self.functions:
            entry = "main"
        elif "Main" in self.functions:
            entry = "Main"
        else:
            raise InterpreterError("entry function main not found")

        result = self.call_function(entry, [])
        if result is None:
            return 0
        if isinstance(result, bool):
            return int(result)
        if isinstance(result, int):
            return result
        raise InterpreterError(f"entry function must return i32/unit, got {type(result).__name__}")

    def call_function(self, name: str, args: list[Any]) -> Any:
        if name == "println":
            print("" if not args else self._stringify(args[0]))
            return None
        if name == "eprintln":
            import sys

            print("" if not args else self._stringify(args[0]), file=sys.stderr)
            return None

        fn = self.functions.get(name)
        if fn is None:
            raise InterpreterError(f"unknown function {name}")

        if len(args) != len(fn.sig.params):
            raise InterpreterError(
                f"function {name} expects {len(fn.sig.params)} args, got {len(args)}"
            )

        env = {param.name: value for param, value in zip(fn.sig.params, args)}
        try:
            return self.eval_block(fn.body, env)
        except ReturnSignal as signal:
            return signal.value

    def eval_block(self, block: BlockExpr | None, env: dict[str, Any]) -> Any:
        if block is None:
            return None
        local = dict(env)
        for stmt in block.statements:
            self.eval_stmt(stmt, local)
        if block.final_expr is not None:
            return self.eval_expr(block.final_expr, local)
        return None

    def eval_stmt(self, stmt: LetStmt | AssignStmt | IncrementStmt | CForStmt | ReturnStmt | ExprStmt, env: dict[str, Any]) -> None:
        if isinstance(stmt, LetStmt):
            env[stmt.name] = self.eval_expr(stmt.value, env)
            return
        if isinstance(stmt, AssignStmt):
            if stmt.name not in env:
                raise InterpreterError(f"unknown name {stmt.name}")
            env[stmt.name] = self.eval_expr(stmt.value, env)
            return
        if isinstance(stmt, IncrementStmt):
            if stmt.name not in env:
                raise InterpreterError(f"unknown name {stmt.name}")
            env[stmt.name] = int(env[stmt.name]) + 1
            return
        if isinstance(stmt, CForStmt):
            loop_env = dict(env)
            self.eval_stmt(stmt.init, loop_env)
            while self.eval_expr(stmt.condition, loop_env):
                self.eval_block(stmt.body, loop_env)
                self.eval_stmt(stmt.step, loop_env)
            for name in list(env.keys()):
                if name in loop_env:
                    env[name] = loop_env[name]
            return
        if isinstance(stmt, ReturnStmt):
            value = self.eval_expr(stmt.value, env) if stmt.value is not None else None
            raise ReturnSignal(value)
        if isinstance(stmt, ExprStmt):
            self.eval_expr(stmt.expr, env)
            return
        raise InterpreterError(f"unsupported statement {type(stmt).__name__}")

    def eval_expr(self, expr: Expr | None, env: dict[str, Any]) -> Any:
        if expr is None:
            return None
        if isinstance(expr, IntExpr):
            return int(expr.value.replace("_", ""))
        if isinstance(expr, StringExpr):
            return expr.value[1:-1]
        if isinstance(expr, BoolExpr):
            return expr.value
        if isinstance(expr, NameExpr):
            if expr.name in env:
                return env[expr.name]
            raise InterpreterError(f"unknown name {expr.name}")
        if isinstance(expr, CallExpr):
            callee = self.eval_callee(expr.callee)
            args = [self.eval_expr(arg, env) for arg in expr.args]
            return self.call_function(callee, args)
        if isinstance(expr, BinaryExpr):
            left = self.eval_expr(expr.left, env)
            right = self.eval_expr(expr.right, env)
            return self.eval_binary(expr.op, left, right)
        if isinstance(expr, IfExpr):
            if self.eval_expr(expr.condition, env):
                return self.eval_block(expr.then_branch, env)
            if expr.else_branch is not None:
                return self.eval_expr(expr.else_branch, env)
            return None
        if isinstance(expr, BlockExpr):
            return self.eval_block(expr, env)
        raise InterpreterError(f"unsupported expression {type(expr).__name__}")

    def eval_callee(self, expr: Expr) -> str:
        if isinstance(expr, NameExpr):
            return expr.name
        raise InterpreterError(f"unsupported callee {type(expr).__name__}")

    def eval_binary(self, op: str, left: Any, right: Any) -> Any:
        if op == "+":
            return left + right
        if op == "-":
            return left - right
        if op == "*":
            return left * right
        if op == "/":
            return left // right
        if op == "==":
            return left == right
        if op == "!=":
            return left != right
        if op == "<":
            return left < right
        if op == "<=":
            return left <= right
        if op == ">":
            return left > right
        if op == ">=":
            return left >= right
        if op == "&&":
            return bool(left) and bool(right)
        if op == "||":
            return bool(left) or bool(right)
        raise InterpreterError(f"unsupported binary operator {op}")

    def _stringify(self, value: Any) -> str:
        if value is None:
            return "()"
        if value is True:
            return "true"
        if value is False:
            return "false"
        return str(value)
