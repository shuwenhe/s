from __future__ import annotations

import argparse
import sys
import subprocess
import tempfile
from pathlib import Path

from compiler.ast import SourceFile
from compiler.backend_elf64 import build_executable as legacy_build_executable
from compiler.internal.amd64 import Init as amd64_init, arch_name as amd64_arch_name, link_program
from compiler.internal.base import ArchInfo, CliError, detect_host_arch, parse_command, resolve_output_path
from compiler.internal.base.config import BUILD_OUTPUT_ROOT
from compiler.internal.ir import MIRProgram, lower_source
from compiler.internal.ssagen import BackendError, lower_program
from compiler.internal.syntax.api import read_source
from compiler.internal.syntax.lexer import Lexer
from compiler.internal.syntax.parser import ParseError, parse_source
from compiler.internal.syntax.tokens import dump_tokens
from compiler.internal.typecheck import check_source
from compiler.internal.typecheck.borrow import VarState, analyze_block
from compiler.internal.typecheck.ownership import make_plan
from compiler.internal.typecheck.types import parse_type
from compiler.ast import dump_source_file, FunctionDecl

ARCH_INITS = {
    "amd64": amd64_init,
}


def run_cli(argv: list[str]) -> int:
    try:
        command = parse_command(argv)
        source = LoadSource(command.path)
        parsed = ParsePhase(command, source)
        TypecheckPhase(parsed)
        BorrowPhase(parsed)
        if command.command == "check":
            print(f"ok: {command.path}")
            return 0
        ownership_plan = OwnershipPhase(parsed)
        mir = LowerToIR(parsed, ownership_plan)
        if command.command == "build":
            emit_binary(parsed, mir, command.output)
            print(f"built: {command.output}")
            return 0
        if command.command == "run":
            return run_source(parsed, mir, command.run_args)
        raise CliError(f"unknown command: {command.command}")
    except CliError as exc:
        print(f"error: {exc.message}", file=sys.stderr)
        return 1


def LoadSource(path: str) -> str:
    return read_source(path)


def ParsePhase(command, source: str) -> SourceFile:
    if command.dump_tokens:
        print(dump_tokens(Lexer(source).tokenize()))
    try:
        parsed = parse_source(source)
    except ParseError as exc:
        raise CliError(f"parse error: {exc}") from exc
    if command.dump_ast:
        print(dump_source_file(parsed))
    return parsed


def TypecheckPhase(parsed: SourceFile) -> None:
    result = check_source(parsed)
    if not result.ok:
        for diagnostic in result.diagnostics:
            print(f"error: {diagnostic.message}", file=sys.stderr)
        raise CliError("semantic check failed")


def BorrowPhase(parsed: SourceFile) -> None:
    diagnostics: list[str] = []
    for item in parsed.items:
        if not isinstance(item, FunctionDecl) or item.body is None:
            continue
        initial: dict[str, VarState] = {
            param.name: VarState(parse_type(param.type_name))
            for param in item.sig.params
        }
        for diag in analyze_block(item.body, initial):
            diagnostics.append(diag.message)
    if diagnostics:
        for message in diagnostics:
            print(f"error: {message}", file=sys.stderr)
        raise CliError("borrow check failed")


def OwnershipPhase(parsed: SourceFile):
    type_env = {}
    for item in parsed.items:
        if isinstance(item, FunctionDecl):
            for param in item.sig.params:
                type_env[param.name] = parse_type(param.type_name)
    return make_plan(type_env)


def LowerToIR(parsed: SourceFile, ownership_plan) -> MIRProgram:
    try:
        return lower_source(parsed, ownership_plan)
    except Exception as exc:  # noqa: BLE001
        raise CliError(f"ir lowering failed: {exc}") from exc


def CodegenPhase(mir: MIRProgram):
    _init_arch()
    return lower_program(mir, amd64_arch_name())


def LinkPhase(program, output_path: str) -> None:
    try:
        link_program(program, resolve_output_path(output_path))
    except BackendError as exc:
        raise CliError(f"backend error: {exc}") from exc


def emit_binary(parsed: SourceFile, mir: MIRProgram, output_path: str) -> None:
    resolved_output = resolve_output_path(output_path)
    if parsed.package == "runtime.runner":
        try:
            legacy_build_executable(parsed, resolved_output)
            return
        except BackendError as exc:
            raise CliError(f"backend error: {exc}") from exc
    program = CodegenPhase(mir)
    LinkPhase(program, str(resolved_output))


def run_source(parsed: SourceFile, mir: MIRProgram, run_args: tuple[str, ...]) -> int:
    try:
        BUILD_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="s-run-", dir=str(BUILD_OUTPUT_ROOT)) as tmp:
            output_path = Path(tmp) / "run-target"
            emit_binary(parsed, mir, str(output_path))
            completed = subprocess.run(
                [str(output_path), *run_args],
                check=False,
                capture_output=True,
                text=True,
            )
            if completed.stdout:
                print(completed.stdout, end="")
            if completed.stderr:
                print(completed.stderr, end="", file=sys.stderr)
            return int(completed.returncode)
    except OSError as exc:
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
