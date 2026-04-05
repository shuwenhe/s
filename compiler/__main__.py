from __future__ import annotations

import argparse
from pathlib import Path
import sys

from compiler.ast import dump_source_file
from compiler.backend_elf64 import BackendError, build_executable
from compiler.interpreter import Interpreter, InterpreterError
from compiler.lexer import Lexer, dump_tokens
from compiler.parser import ParseError, parse_source
from compiler.semantic import check_source


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="s")
    sub = parser.add_subparsers(dest="command", required=True)

    check_cmd = sub.add_parser("check", help="parse and type-check an S source file")
    check_cmd.add_argument("path")
    check_cmd.add_argument("--dump-tokens", action="store_true")
    check_cmd.add_argument("--dump-ast", action="store_true")

    build_cmd = sub.add_parser("build", help="build a minimal S source file into a native binary")
    build_cmd.add_argument("path")
    build_cmd.add_argument("-o", "--output", required=True)

    run_cmd = sub.add_parser("run", help="interpret a minimal S source file")
    run_cmd.add_argument("path")

    args = parser.parse_args(argv)
    if args.command == "check":
        return run_check(args.path, dump_tokens_flag=args.dump_tokens, dump_ast_flag=args.dump_ast)
    if args.command == "build":
        return build_source(args.path, args.output)
    if args.command == "run":
        return run_source(args.path)
    parser.error("unknown command")
    return 2


def run_check(path: str, dump_tokens_flag: bool, dump_ast_flag: bool) -> int:
    source_path = Path(path)
    source = source_path.read_text()
    if dump_tokens_flag:
        print(dump_tokens(Lexer(source).tokenize()))
    try:
        parsed = parse_source(source)
    except ParseError as exc:
        print(f"parse error: {exc}", file=sys.stderr)
        return 1
    if dump_ast_flag:
        print(dump_source_file(parsed))
    result = check_source(parsed)
    if not result.ok:
        for diagnostic in result.diagnostics:
            print(f"error: {diagnostic.message}", file=sys.stderr)
        return 1
    print(f"ok: {source_path}")
    return 0


def run_source(path: str) -> int:
    source_path = Path(path)
    source = source_path.read_text()
    try:
        parsed = parse_source(source)
    except ParseError as exc:
        print(f"parse error: {exc}", file=sys.stderr)
        return 1

    result = check_source(parsed)
    if not result.ok:
        for diagnostic in result.diagnostics:
            print(f"error: {diagnostic.message}", file=sys.stderr)
        return 1

    try:
        return Interpreter(parsed).run_main()
    except InterpreterError as exc:
        print(f"runtime error: {exc}", file=sys.stderr)
        return 1


def build_source(path: str, output: str) -> int:
    source_path = Path(path)
    output_path = Path(output)
    source = source_path.read_text()
    try:
        parsed = parse_source(source)
    except ParseError as exc:
        print(f"parse error: {exc}", file=sys.stderr)
        return 1

    result = check_source(parsed)
    if not result.ok:
        for diagnostic in result.diagnostics:
            print(f"error: {diagnostic.message}", file=sys.stderr)
        return 1

    try:
        build_executable(parsed, output_path.resolve())
    except BackendError as exc:
        print(f"backend error: {exc}", file=sys.stderr)
        return 1

    print(f"built: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
