from __future__ import annotations

import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from compiler.ast import FunctionDecl, ImplDecl, SourceFile, dump_source_file
from compiler.backend_elf64 import build_executable as legacy_build_executable
from compiler.internal.amd64 import Init as amd64_init, arch_name as amd64_arch_name, link_program
from compiler.internal.base import ArchInfo, CliError, detect_host_arch, parse_command, resolve_output_path
from compiler.internal.base.config import BUILD_OUTPUT_ROOT
from compiler.internal.ir import MIRFunction, MIRProgram, lower_function, merge_mir_programs
from compiler.internal.ssagen import BackendError, lower_program
from compiler.internal.syntax.api import read_source
from compiler.internal.syntax.lexer import Lexer
from compiler.internal.syntax.parser import ParseError, parse_source
from compiler.internal.syntax.tokens import dump_tokens
from compiler.internal.typecheck import check_source
from compiler.internal.typecheck.borrow import VarState, analyze_block
from compiler.internal.typecheck.ownership import make_plan
from compiler.internal.typecheck.types import parse_type

ARCH_INITS = {
    "amd64": amd64_init,
}


@dataclass(frozen=True)
class FrontendResult:
    command: object
    source: str
    parsed: SourceFile


@dataclass(frozen=True)
class CompileResult:
    frontend: FrontendResult
    queue: "CompileQueue"
    ownership_plan: object
    mir: MIRProgram


@dataclass(frozen=True)
class FunctionCompileUnit:
    name: str
    decl: FunctionDecl
    origin: str
    prepared: bool = False
    compiled: bool = False


@dataclass(frozen=True)
class CompileQueue:
    units: tuple[FunctionCompileUnit, ...]
    entry_name: str = ""


def run_cli(argv: list[str]) -> int:
    try:
        command = parse_command(argv)
        frontend = FrontendPhase(command)
        if command.command == "check":
            print(f"ok: {command.path}")
            return 0

        compiled = CompilePhase(frontend)
        if command.command == "build":
            emit_binary(compiled, command.output)
            print(f"built: {command.output}")
            return 0
        if command.command == "run":
            return run_binary(compiled, command.run_args)
        raise CliError(f"unknown command: {command.command}")
    except CliError as exc:
        print(f"error: {exc.message}", file=sys.stderr)
        return 1


def FrontendPhase(command) -> FrontendResult:
    source = LoadSource(command.path)
    parsed = ParsePhase(command, source)
    TypecheckPhase(parsed)
    BorrowPhase(parsed)
    return FrontendResult(command=command, source=source, parsed=parsed)


def CompilePhase(frontend: FrontendResult) -> CompileResult:
    queue = PrepareCompileQueue(frontend.parsed)
    ownership_plan = OwnershipPhase(frontend.parsed)
    mir, compiled_queue = CompileFunctions(frontend, queue, ownership_plan)
    return CompileResult(frontend=frontend, queue=compiled_queue, ownership_plan=ownership_plan, mir=mir)


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


def PrepareFunc(fn: FunctionDecl, origin: str) -> FunctionCompileUnit | None:
    if fn.sig.name == "_" or fn.body is None:
        return None
    return FunctionCompileUnit(
        name=fn.sig.name,
        decl=fn,
        origin=origin,
        prepared=True,
    )


def EnqueueFunc(queue: list[FunctionCompileUnit], fn: FunctionDecl, origin: str) -> None:
    prepared = PrepareFunc(fn, origin)
    if prepared is not None:
        queue.append(prepared)


def PrepareCompileQueue(parsed: SourceFile) -> CompileQueue:
    units: list[FunctionCompileUnit] = []
    entry_name = ""

    for item in parsed.items:
        if isinstance(item, FunctionDecl):
            EnqueueFunc(units, item, parsed.package)
            if item.sig.name == "main":
                entry_name = item.sig.name
            continue
        if isinstance(item, ImplDecl):
            for method in item.methods:
                EnqueueFunc(units, method, f"{parsed.package}.impl.{item.target}")

    return CompileQueue(units=tuple(units), entry_name=entry_name)


def LowerToIR(
    frontend: FrontendResult,
    unit: FunctionCompileUnit,
    ownership_plan,
    *,
    is_entry: bool,
) -> MIRFunction:
    try:
        return lower_function(
            frontend.parsed,
            unit.decl,
            ownership_plan,
            is_entry=is_entry,
        )
    except Exception as exc:  # noqa: BLE001
        raise CliError(f"ir lowering failed: {exc}") from exc


def CompileFunctions(
    frontend: FrontendResult,
    queue: CompileQueue,
    ownership_plan,
) -> tuple[MIRProgram, CompileQueue]:
    functions: list[MIRFunction] = []
    for unit in queue.units:
        functions.append(LowerToIR(frontend, unit, ownership_plan, is_entry=unit.name == queue.entry_name))
    mir = merge_mir_programs(frontend.parsed, functions, entry_name=queue.entry_name)
    compiled_units = tuple(
        FunctionCompileUnit(
            name=unit.name,
            decl=unit.decl,
            origin=unit.origin,
            prepared=unit.prepared,
            compiled=True,
        )
        for unit in queue.units
    )
    return mir, CompileQueue(units=compiled_units, entry_name=queue.entry_name)


def CodegenPhase(mir: MIRProgram):
    _init_arch()
    return lower_program(mir, amd64_arch_name())


def LinkPhase(program, output_path: str) -> None:
    try:
        link_program(program, resolve_output_path(output_path))
    except BackendError as exc:
        raise CliError(f"backend error: {exc}") from exc


def emit_binary(compiled: CompileResult, output_path: str) -> None:
    resolved_output = resolve_output_path(output_path)
    parsed = compiled.frontend.parsed
    if parsed.package == "runtime.runner":
        try:
            legacy_build_executable(parsed, resolved_output)
            return
        except BackendError as exc:
            raise CliError(f"backend error: {exc}") from exc
    program = CodegenPhase(compiled.mir)
    LinkPhase(program, str(resolved_output))


def run_binary(compiled: CompileResult, run_args: tuple[str, ...]) -> int:
    try:
        BUILD_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="s-run-", dir=str(BUILD_OUTPUT_ROOT)) as tmp:
            output_path = Path(tmp) / "run-target"
            emit_binary(compiled, str(output_path))
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


def _init_arch() -> ArchInfo:
    arch_name = detect_host_arch()
    arch_init = ARCH_INITS.get(arch_name)
    if arch_init is None:
        raise CliError(f"unsupported architecture: {arch_name}")
    info = ArchInfo(name=arch_name)
    arch_init(info)
    return info
