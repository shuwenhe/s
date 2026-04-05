from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys

from compiler.ast import SourceFile, dump_source_file
from compiler.backend_elf64 import BackendError, build_executable
from compiler.lexer import Lexer, dump_tokens
from compiler.parser import ParseError, parse_source
from compiler.semantic import check_source


@dataclass(frozen=True)
class CliError(Exception):
    message: str

    def __str__(self) -> str:
        return self.message


@dataclass(frozen=True)
class CheckOptions:
    command: str
    path: str
    output: str = ""
    dump_tokens: bool = False
    dump_ast: bool = False


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
        raise CliError(f"unknown command: {command.command}")
    except CliError as exc:
        print(f"error: {exc.message}", file=sys.stderr)
        return 1


def parse_command(argv: list[str]) -> CheckOptions:
    if len(argv) < 2:
        raise _usage_error()
    command = argv[0]
    if command not in {"check", "build"}:
        raise _usage_error()
    if len(argv) < 2:
        raise _usage_error()

    if command == "build":
        if len(argv) < 4:
            raise _usage_error()
        if argv[2] != "-o":
            raise CliError("expected -o before output path")
        return CheckOptions(command=command, path=argv[1], output=argv[3])

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


def read_source(path: str) -> str:
    source_path = Path(path)
    try:
        return source_path.read_text()
    except OSError as exc:
        raise CliError(f"failed to read source file: {path}") from exc


def parse_checked_source(command: CheckOptions, source: str) -> SourceFile:
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


def emit_binary(parsed: SourceFile, output_path: str) -> None:
    try:
        build_executable(parsed, Path(output_path).resolve())
    except BackendError as exc:
        raise CliError(f"backend error: {exc}") from exc


def _usage_error() -> CliError:
    return CliError("usage: s check <path> [--dump-tokens] [--dump-ast] | s build <path> -o <output>")
