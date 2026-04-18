from __future__ import annotations

from dataclasses import dataclass
from pathlib import path
import os
import subprocess
import sys

from compiler.ast import sourcefile, dump_source_file
from compiler.backend_elf64 import backenderror, build_executable
from compiler.interpreter import interpreter, interpretererror
from compiler.lexer import lexer, dump_tokens
from compiler.parser import parseerror, parse_source
from compiler.semantic import check_source

build_output_root = path(os.environ.get("s_build_output_root", "/tmp/s-build"))
selfhosted_runner_paths = (
    path(os.environ.get("s_selfhosted_runner", "")) if os.environ.get("s_selfhosted_runner") else none,
    path("/app/s/bin/s-selfhosted"),
    path(__file__).resolve().parents[2] / "bin" / "s-selfhosted",
)


@dataclass(frozen=true)
class clierror(exception):
    message: str

    def __str__(self) -> str:
        return self.message


@dataclass(frozen=true)
class checkoptions:
    command: str
    path: str
    output: str = ""
    dump_tokens: bool = false
    dump_ast: bool = false


def run_cli(argv: list[str]) -> int:
    try:
        command = parse_command(argv)
        selfhosted_runner = resolve_selfhosted_runner()
        if selfhosted_runner is not none and can_selfhosted_handle(command):
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
        raise clierror(f"unknown command: {command.command}")
    except clierror as exc:
        print(f"error: {exc.message}", file=sys.stderr)
        return 1
    except interpretererror as exc:
        print(f"runtime error: {exc}", file=sys.stderr)
        return 1


def can_selfhosted_handle(command: checkoptions) -> bool:
    return not command.dump_tokens and not command.dump_ast


def resolve_selfhosted_runner() -> path | none:
    for candidate in selfhosted_runner_paths:
        if candidate is none:
            continue
        if candidate.is_file() and os.access(candidate, os.x_ok):
            return candidate
    return none


def run_selfhosted_cli(selfhosted_runner: path, command: checkoptions) -> int:
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
        raise clierror(f"unknown command: {command.command}")

    completed = subprocess.run(args, check=false)
    return int(completed.returncode)


def parse_command(argv: list[str]) -> checkoptions:
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
            raise clierror("expected -o before output path")
        return checkoptions(command=command, path=argv[1], output=str(resolve_output_path(argv[3])))
    if command == "run":
        if len(argv) != 2:
            raise _usage_error()
        return checkoptions(command=command, path=argv[1])

    options = checkoptions(command=command, path=argv[1])
    index = 2
    dump_tokens_flag = false
    dump_ast_flag = false
    while index < len(argv):
        flag = argv[index]
        if flag == "--dump-tokens":
            dump_tokens_flag = true
        elif flag == "--dump-ast":
            dump_ast_flag = true
        else:
            raise clierror(f"unknown flag: {flag}")
        index += 1
    return checkoptions(
        command=options.command,
        path=options.path,
        output=options.output,
        dump_tokens=dump_tokens_flag,
        dump_ast=dump_ast_flag,
    )


def read_source(path: str) -> str:
    source_path = path(path)
    try:
        return source_path.read_text()
    except oserror as exc:
        raise clierror(f"failed to read source file: {path}") from exc


def parse_checked_source(command: checkoptions, source: str) -> sourcefile:
    if command.dump_tokens:
        print(dump_tokens(lexer(source).tokenize()))

    try:
        parsed = parse_source(source)
    except parseerror as exc:
        raise clierror(f"parse error: {exc}") from exc

    if command.dump_ast:
        print(dump_source_file(parsed))

    result = check_source(parsed)
    if not result.ok:
        for diagnostic in result.diagnostics:
            print(f"error: {diagnostic.message}", file=sys.stderr)
        raise clierror("semantic check failed")

    return parsed


def emit_binary(parsed: sourcefile, output_path: str) -> none:
    try:
        build_executable(parsed, resolve_output_path(output_path))
    except backenderror as exc:
        raise clierror(f"backend error: {exc}") from exc


def run_checked_source(parsed: sourcefile) -> int:
    return interpreter(parsed).run_main()


def resolve_output_path(output_path: str) -> path:
    target = path(output_path)
    if not target.is_absolute():
        target = build_output_root / target.name
    target.parent.mkdir(parents=true, exist_ok=true)
    return target.resolve()


def _usage_error() -> clierror:
    return clierror(
        "usage: s check <path> [--dump-tokens] [--dump-ast] | "
        "s build <path> -o <output> | s run <path>"
    )
