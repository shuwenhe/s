from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from compiler.internal.base.config import BUILD_OUTPUT_ROOT


@dataclass(frozen=True)
class CliError(Exception):
    message: str

    def __str__(self) -> str:
        return self.message


@dataclass(frozen=True)
class CommandOptions:
    command: str
    path: str
    output: str = ""
    dump_tokens: bool = False
    dump_ast: bool = False
    run_args: tuple[str, ...] = ()


def parse_command(argv: list[str]) -> CommandOptions:
    if len(argv) < 2:
        raise usage_error()
    command = argv[0]
    if command not in {"check", "build", "run"}:
        raise usage_error()

    if command == "build":
        if len(argv) < 4:
            raise usage_error()
        if argv[2] != "-o":
            raise CliError("expected -o before output path")
        return CommandOptions(command=command, path=argv[1], output=str(resolve_output_path(argv[3])))

    if command == "run":
        return CommandOptions(command=command, path=argv[1], run_args=tuple(argv[2:]))

    dump_tokens = False
    dump_ast = False
    for flag in argv[2:]:
        if flag == "--dump-tokens":
            dump_tokens = True
        elif flag == "--dump-ast":
            dump_ast = True
        else:
            raise CliError(f"unknown flag: {flag}")

    return CommandOptions(
        command=command,
        path=argv[1],
        dump_tokens=dump_tokens,
        dump_ast=dump_ast,
    )


def resolve_output_path(output_path: str) -> Path:
    target = Path(output_path)
    if not target.is_absolute():
        target = BUILD_OUTPUT_ROOT / target.name
    target.parent.mkdir(parents=True, exist_ok=True)
    return target.resolve()


def usage_error() -> CliError:
    return CliError(
        "usage: s check <path> [--dump-tokens] [--dump-ast] | "
        "s build <path> -o <output> | s run <path> [args...]"
    )
