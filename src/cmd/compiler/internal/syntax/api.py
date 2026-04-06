from __future__ import annotations

from pathlib import Path
import sys

from compiler.ast import SourceFile, dump_source_file
from compiler.internal.base import CliError, CommandOptions
from compiler.internal.syntax.lexer import Lexer
from compiler.internal.syntax.parser import ParseError, parse_source
from compiler.internal.syntax.tokens import dump_tokens
from compiler.internal.typecheck import check_source


def read_source(path: str) -> str:
    source_path = Path(path)
    try:
        return source_path.read_text()
    except OSError as exc:
        raise CliError(f"failed to read source file: {path}") from exc


def parse_checked_source(command: CommandOptions, source: str) -> SourceFile:
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
