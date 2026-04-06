from __future__ import annotations

import argparse
import sys

from compiler.ast import SourceFile
from compiler.internal.amd64 import Init as amd64_init
from compiler.internal.base import ArchInfo, CliError, detect_host_arch, parse_command, resolve_output_path
from compiler.internal.gc.interpreter import Interpreter, InterpreterError
from compiler.internal.ssagen import BackendError
from compiler.internal.syntax import parse_checked_source, read_source

ARCH_INITS = {
    "amd64": amd64_init,
}


def run_cli(argv: list[str]) -> int:
    try:
        command = parse_command(argv)
        source = read_source(command.path)
        parsed = parse_checked_source(command, source)
        if command.command == "check":
            print(f"ok: {command.path}")
            return 0
        if command.command == "build":
            emit_binary(parsed, command.output)
            print(f"built: {command.output}")
            return 0
        if command.command == "run":
            return run_source(parsed, command.run_args)
        raise CliError(f"unknown command: {command.command}")
    except CliError as exc:
        print(f"error: {exc.message}", file=sys.stderr)
        return 1


def emit_binary(parsed: SourceFile, output_path: str) -> None:
    arch = _init_arch()
    try:
        assert arch.emitter is not None
        arch.emitter(parsed, resolve_output_path(output_path))
    except BackendError as exc:
        raise CliError(f"backend error: {exc}") from exc


def run_source(parsed: SourceFile, run_args: tuple[str, ...]) -> int:
    try:
        interpreter = Interpreter(parsed)
        interpreter.argv = list(run_args)
        return int(interpreter.run_main())
    except InterpreterError as exc:
        raise CliError(f"runtime error: {exc}") from exc


def Main(argv: list[str] | None = None) -> int:
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
    run_cmd.add_argument("program_args", nargs="*", metavar="arg")

    args = parser.parse_args(argv)
    if args.command == "check":
        cmd = [args.command, args.path]
        if args.dump_tokens:
            cmd.append("--dump-tokens")
        if args.dump_ast:
            cmd.append("--dump-ast")
        return run_cli(cmd)
    if args.command == "build":
        return run_cli([args.command, args.path, "-o", args.output])
    if args.command == "run":
        return run_cli([args.command, args.path, *args.program_args])
    parser.error("unknown command")
    return 2


def _init_arch() -> ArchInfo:
    arch_name = detect_host_arch()
    arch_init = ARCH_INITS.get(arch_name)
    if arch_init is None:
        raise CliError(f"unsupported architecture: {arch_name}")
    info = ArchInfo(name=arch_name)
    arch_init(info)
    return info
