from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os
import subprocess
import sys

from compiler.ast import SourceFile, dump_source_file
from compiler.backend_elf64 import BackendError, build_executable
from compiler.interpreter import Interpreter, InterpreterError
from compiler.lexer import Lexer, dump_tokens
from compiler.parser import ParseError, parse_source
from compiler.semantic import check_source

BUILD_OUTPUT_ROOT = Path(os.environ.get("S_BUILD_OUTPUT_ROOT", "/tmp/s-build"))
SELFHOSTED_RUNNER_PATHS = (
    Path(os.environ.get("S_SELFHOSTED_RUNNER", "")) if os.environ.get("S_SELFHOSTED_RUNNER") else None,
    Path("/app/s/bin/s-selfhosted"),
    Path(__file__).resolve().parents[2] / "bin" / "s-selfhosted",
)


@dataclass(frozen=True)
class CliError(Exception):
    message: str

    def __str__(self)  str:
        return self.message


@dataclass(frozen=True)
class CheckOptions:
    command: str
    path: str
    output: str = ""
    dump_tokens: bool = False
    dump_ast: bool = False


def run_cli(argv: list[str])  int:
    try:
        command = parse_command(argv)
        selfhosted_runner = resolve_selfhosted_runner()
        if selfhosted_runner is not None and can_selfhosted_handle(command):
            return run_selfhosted_cli(selfhosted_runner, command)
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
            return run_checked_source(parsed)
        raise CliError(f"unknown command: {command.command}")
    except CliError as exc:
        print(f"error: {exc.message}", file=sys.stderr)
        return 1
    except InterpreterError as exc:
        print(f"runtime error: {exc}", file=sys.stderr)
        return 1


def can_selfhosted_handle(command: CheckOptions)  bool:
    return not command.dump_tokens and not command.dump_ast


def resolve_selfhosted_runner()  Path | None:
    for candidate in SELFHOSTED_RUNNER_PATHS:
        if candidate is None:
            continue
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def run_selfhosted_cli(selfhosted_runner: Path, command: CheckOptions)  int:
    if command.command == "check":
        args = [str(selfhosted_runner), "check", command.path]
        if command.dump_tokens:
            args.append("--dump-tokens")
        if command.dump_ast:
            args.append("--dump-ast")
    elif command.command == "build":
        args = [str(selfhosted_runner), "build", command.path, "-o", command.output]
    elif command.command == "run":
        args = [str(selfhosted_runner), "run", command.path]
    else:
        raise CliError(f"unknown command: {command.command}")

    completed = subprocess.run(args, check=False)
    return int(completed.returncode)


def parse_command(argv: list[str])  CheckOptions:
    if len(argv) < 2:
        raise _usage_error()
    command = argv[0]
    if command not in {"check", "build", "run"}:
        raise _usage_error()
    if len(argv) < 2:
        raise _usage_error()

    if command == "build":
        if len(argv) < 4:
            raise _usage_error()
        if argv[2] != "-o":
            raise CliError("expected -o before output path")
        return CheckOptions(command=command, path=argv[1], output=str(resolve_output_path(argv[3])))
    if command == "run":
        if len(argv) != 2:
            raise _usage_error()
        return CheckOptions(command=command, path=argv[1])

    options = CheckOptions(command=command, path=argv[1])
    index = 2
    dump_tokens_flag = False
    dump_ast_flag = False
    while index < len(argv):
        flag = argv[index]
        if flag == "--dump-tokens":
            dump_tokens_flag = True
        elif flag == "--dump-ast":
            dump_ast_flag = True
        else:
            raise CliError(f"unknown flag: {flag}")
        index += 1
    return CheckOptions(
        command=options.command,
        path=options.path,
        output=options.output,
        dump_tokens=dump_tokens_flag,
        dump_ast=dump_ast_flag,
    )


def read_source(path: str)  str:
    source_path = Path(path)
    try:
        return source_path.read_text()
    except OSError as exc:
        raise CliError(f"failed to read source file: {path}") from exc


def parse_checked_source(command: CheckOptions, source: str)  SourceFile:
    if command.dump_tokens:
        print(dump_tokens(Lexer(source).tokenize()))

    try:
        parsed = parse_source(source)
    except ParseError as exc:
        raise CliError(f"parse error: {exc}") from exc

    if command.dump_ast:
        print(dump_source_file(parsed))

    result = check_source(parsed)
    if not result.ok:
        for diagnostic in result.diagnostics:
            print(f"error: {diagnostic.message}", file=sys.stderr)
        raise CliError("semantic check failed")

    return parsed


def emit_binary(parsed: SourceFile, output_path: str)  None:
    try:
        build_executable(parsed, resolve_output_path(output_path))
    except BackendError as exc:
        raise CliError(f"backend error: {exc}") from exc


def run_checked_source(parsed: SourceFile)  int:
    return Interpreter(parsed).run_main()


def resolve_output_path(output_path: str)  Path:
    target = Path(output_path)
    if not target.is_absolute():
        target = BUILD_OUTPUT_ROOT / target.name
    target.parent.mkdir(parents=True, exist_ok=True)
    return target.resolve()


def _usage_error()  CliError:
    return CliError(
        "usage: s check <path> [--dump-tokens] [--dump-ast] | "
        "s build <path> -o <output> | s run <path>"
    )
