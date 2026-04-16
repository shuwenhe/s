from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os
import subprocess
import tempfile
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
    IndexExpr,
    IntExpr,
    LetStmt,
    MatchExpr,
    MatchArm,
    MemberExpr,
    NameExpr,
    Pattern,
    ReturnStmt,
    SourceFile,
    StringExpr,
    VariantPattern,
    WhileExpr,
    WildcardPattern,
    NamePattern,
)
from compiler.parser import parse_source


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
        self.imports = {use.alias or use.path.split(".")[-1]: use.path for use in source.uses}
        self.explicit_exit_code: int | None = None
        self.argv: list[str] = []
        self._package_cache: dict[str, Interpreter] = {}

    def run_main(self) -> int:
        if "main" in self.functions:
            entry = "main"
        elif "Main" in self.functions:
            entry = "Main"
        else:
            raise InterpreterError("entry function main not found")

        result = self.call_function(entry, [])
        if self.explicit_exit_code is not None:
            return self.explicit_exit_code
        if result is None:
            return 0
        if isinstance(result, bool):
            return int(result)
        if isinstance(result, int):
            return result
        raise InterpreterError(f"entry function must return i32/unit, got {type(result).__name__}")

    def call_function(self, name: str, args: list[Any]) -> Any:
        if name in {"Ok", "Err", "Some"}:
            payload = None if not args else args[0]
            return (name, payload)
        if name == "None":
            return ("None", None)
        if name == "println":
            print("" if not args else self._stringify(args[0]))
            return None
        if name == "eprintln":
            import sys

            print("" if not args else self._stringify(args[0]), file=sys.stderr)
            return None
        if name == "__host_args":
            return list(self.argv)
        if name == "__host_get_env":
            value = os.environ.get("" if not args else str(args[0]))
            if value is None:
                return ("None", None)
            return ("Some", value)
        if name == "__host_read_to_string":
            try:
                return ("Ok", Path(str(args[0])).read_text())
            except OSError as exc:
                return ("Err", {"message": str(exc)})
        if name == "__host_write_text_file":
            try:
                Path(str(args[0])).write_text("" if len(args) < 2 else str(args[1]))
                return ("Ok", None)
            except OSError as exc:
                return ("Err", {"message": str(exc)})
        if name == "__host_make_temp_dir":
            try:
                path = tempfile.mkdtemp(prefix="" if not args else str(args[0]))
                return ("Ok", path)
            except OSError as exc:
                return ("Err", {"message": str(exc)})
        if name == "__host_run_process":
            try:
                subprocess.run([str(arg) for arg in (args[0] if args else [])], check=True, capture_output=True, text=True)
                return ("Ok", None)
            except (OSError, subprocess.CalledProcessError) as exc:
                return ("Err", {"message": str(exc)})
        if name == "__host_exit":
            self.explicit_exit_code = int(args[0]) if args else 0
            return None
        if name == "Args" and self.imports.get("Args") == "std.env.Args":
            return list(self.argv)
        if name == "Exit" and self.imports.get("Exit") == "std.process.Exit":
            self.explicit_exit_code = int(args[0]) if args else 0
            return None
        if name == "ReadToString" and self.imports.get("ReadToString") == "std.fs.ReadToString":
            try:
                return ("Ok", Path(str(args[0])).read_text())
            except OSError as exc:
                return ("Err", {"message": str(exc)})
        if name == "WriteTextFile" and self.imports.get("WriteTextFile") == "std.fs.WriteTextFile":
            try:
                Path(str(args[0])).write_text("" if len(args) < 2 else str(args[1]))
                return ("Ok", None)
            except OSError as exc:
                return ("Err", {"message": str(exc)})
        if name == "MakeTempDir" and self.imports.get("MakeTempDir") == "std.fs.MakeTempDir":
            try:
                path = tempfile.mkdtemp(prefix="" if not args else str(args[0]))
                return ("Ok", path)
            except OSError as exc:
                return ("Err", {"message": str(exc)})
        if name == "RunProcess" and self.imports.get("RunProcess") == "std.process.RunProcess":
            try:
                subprocess.run([str(arg) for arg in (args[0] if args else [])], check=True, capture_output=True, text=True)
                return ("Ok", None)
            except (OSError, subprocess.CalledProcessError) as exc:
                return ("Err", {"message": str(exc)})
        if name == "len" and self.imports.get("len") == "std.prelude.len":
            return len(args[0]) if args else 0
        if name == "to_string" and self.imports.get("to_string") == "std.prelude.to_string":
            return str(args[0]) if args else ""
        if name == "char_at" and self.imports.get("char_at") == "std.prelude.char_at":
            return str(args[0])[int(args[1])]
        if name == "slice" and self.imports.get("slice") == "std.prelude.slice":
            return str(args[0])[int(args[1]) : int(args[2])]

        imported_path = self.imports.get(name)
        if imported_path is not None:
            return self._call_imported_function(imported_path, args)

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

    def _call_imported_function(self, imported_path: str, args: list[Any]) -> Any:
        if imported_path == "std.env.Args":
            return list(self.argv)
        if imported_path == "std.process.Exit":
            self.explicit_exit_code = int(args[0]) if args else 0
            return None

        package_path, func_name = imported_path.rsplit(".", 1)
        imported_interpreter = self._load_imported_package(package_path)
        result = imported_interpreter.call_function(func_name, args)
        if imported_interpreter.explicit_exit_code is not None:
            self.explicit_exit_code = imported_interpreter.explicit_exit_code
        return result

    def _load_imported_package(self, package_path: str) -> "Interpreter":
        cached = self._package_cache.get(package_path)
        if cached is not None:
            return cached

        source_path = self._source_path_for_package(package_path)
        if source_path is None:
            raise InterpreterError(f"unknown imported package {package_path}")
        source_text = source_path.read_text()
        source = parse_source(source_text)
        child = Interpreter(source)
        child.argv = self.argv
        child._package_cache = self._package_cache
        self._package_cache[package_path] = child
        return child

    def _source_path_for_package(self, package_path: str) -> Path | None:
        root = Path(__file__).resolve().parent.parent
        if package_path.startswith("compile.internal."):
            tail = package_path.removeprefix("compile.internal.")
            parts = tail.split(".")
            return root / "cmd" / "compile" / "internal" / Path(*parts) / f"{parts[-1]}.s"
        if package_path.startswith("internal."):
            tail = package_path.removeprefix("internal.")
            parts = tail.split(".")
            return root / "internal" / Path(*parts) / f"{parts[-1]}.s"
        if package_path.startswith("std."):
            tail = package_path.removeprefix("std.")
            if tail == "prelude":
                return root / "prelude" / "prelude.s"
            parts = tail.split(".")
            return root / Path(*parts) / f"{parts[-1]}.s"
        return None

    def eval_block(self, block: BlockExpr | None, env: dict[str, Any]) -> Any:
        if block is None:
            return None
        local = dict(env)
        return self._eval_block_in_place(block, local)

    def _eval_block_in_place(self, block: BlockExpr, env: dict[str, Any]) -> Any:
        for stmt in block.statements:
            self.eval_stmt(stmt, env)
        if block.final_expr is not None:
            return self.eval_expr(block.final_expr, env)
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
                self._eval_block_in_place(stmt.body, loop_env)
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
            return self._decode_string_literal(expr.value)
        if isinstance(expr, BoolExpr):
            return expr.value
        if isinstance(expr, NameExpr):
            if expr.name in env:
                return env[expr.name]
            if expr.name == "None":
                return ("None", None)
            raise InterpreterError(f"unknown name {expr.name}")
        if isinstance(expr, CallExpr):
            constructed = self._eval_type_constructor(expr.callee, expr.args, env)
            if constructed is not None:
                return constructed
            if isinstance(expr.callee, MemberExpr):
                receiver = self.eval_expr(expr.callee.target, env)
                args = [self.eval_expr(arg, env) for arg in expr.args]
                return self.eval_method_call(receiver, expr.callee.member, args)
            callee = self.eval_callee(expr.callee)
            args = [self.eval_expr(arg, env) for arg in expr.args]
            return self.call_function(callee, args)
        if isinstance(expr, BinaryExpr):
            left = self.eval_expr(expr.left, env)
            right = self.eval_expr(expr.right, env)
            return self.eval_binary(expr.op, left, right)
        if isinstance(expr, MemberExpr):
            target = self.eval_expr(expr.target, env)
            if isinstance(target, dict):
                return target.get(expr.member)
            raise InterpreterError(f"unsupported member access {expr.member}")
        if isinstance(expr, IndexExpr):
            target = self.eval_expr(expr.target, env)
            index = self.eval_expr(expr.index, env)
            return target[int(index)]
        if isinstance(expr, IfExpr):
            if self.eval_expr(expr.condition, env):
                return self._eval_block_in_place(expr.then_branch, env)
            if expr.else_branch is not None:
                if isinstance(expr.else_branch, BlockExpr):
                    return self._eval_block_in_place(expr.else_branch, env)
                return self.eval_expr(expr.else_branch, env)
            return None
        if isinstance(expr, WhileExpr):
            while self.eval_expr(expr.condition, env):
                self._eval_block_in_place(expr.body, env)
            return None
        if isinstance(expr, MatchExpr):
            subject = self.eval_expr(expr.subject, env)
            for arm in expr.arms:
                bindings = self._match_pattern(arm.pattern, subject)
                if bindings is None:
                    continue
                arm_env = dict(env)
                arm_env.update(bindings)
                return self.eval_expr(arm.expr, arm_env)
            return None
        if isinstance(expr, BlockExpr):
            return self.eval_block(expr, env)
        raise InterpreterError(f"unsupported expression {type(expr).__name__}")

    def eval_callee(self, expr: Expr) -> str:
        if isinstance(expr, NameExpr):
            return expr.name
        raise InterpreterError(f"unsupported callee {type(expr).__name__}")

    def eval_method_call(self, receiver: Any, member: str, args: list[Any]) -> Any:
        if member == "push" and isinstance(receiver, list):
            if args:
                receiver.append(args[0])
            return None
        if member == "len":
            return len(receiver)
        raise InterpreterError(f"unsupported method {member}")

    def _eval_type_constructor(self, callee: Expr, args: list[Expr], env: dict[str, Any]) -> Any:
        if args:
            return None
        if isinstance(callee, IndexExpr) and isinstance(callee.target, NameExpr) and callee.target.name == "Vec":
            return []
        if isinstance(callee, NameExpr) and callee.name == "Vec":
            return []
        return None

    def _match_pattern(self, pattern: Pattern, value: Any) -> dict[str, Any] | None:
        if isinstance(pattern, WildcardPattern):
            return {}
        if isinstance(pattern, NamePattern):
            return {pattern.name: value}
        if isinstance(pattern, VariantPattern):
            tag = pattern.path.split("::")[-1].split(".")[-1]
            if not isinstance(value, tuple) or len(value) != 2 or value[0] != tag:
                return None
            payload = value[1]
            if not pattern.args:
                return {}
            bindings: dict[str, Any] = {}
            for arg in pattern.args:
                matched = self._match_pattern(arg, payload)
                if matched is None:
                    return None
                bindings.update(matched)
            return bindings
        return None

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
        if isinstance(value, tuple) and len(value) == 2:
            if value[0] == "None":
                return "None"
            return f"{value[0]}({self._stringify(value[1])})"
        if value is True:
            return "true"
        if value is False:
            return "false"
        return str(value)

    def _decode_string_literal(self, literal: str) -> str:
        text = literal[1:-1]
        out: list[str] = []
        index = 0
        while index < len(text):
            ch = text[index]
            if ch != "\\":
                out.append(ch)
                index += 1
                continue
            if index + 1 >= len(text):
                out.append("\\")
                break
            esc = text[index + 1]
            if esc == "n":
                out.append("\n")
            elif esc == "t":
                out.append("\t")
            elif esc == '"':
                out.append('"')
            elif esc == "\\":
                out.append("\\")
            else:
                out.append(esc)
            index += 2
        return "".join(out)
