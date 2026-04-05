from __future__ import annotations

import argparse
from pathlib import Path
import tempfile

from slatec.backend_elf64 import BackendError, build_executable
from slatec.lexer import LexError, Lexer
from slatec.parser import ParseError, Parser
from slatec.semantic import SemanticError, check


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="slatec")
    sub = parser.add_subparsers(dest="command", required=True)

    build_cmd = sub.add_parser("build", help="build an S source file into a native binary")
    build_cmd.add_argument("path")
    build_cmd.add_argument("-o", "--output", required=True)

    args = parser.parse_args(argv)
    if args.command == "build":
        return build(Path(args.path), Path(args.output))
    parser.error("unknown command")
    return 2


def build(path: Path, output: Path) -> int:
    source_text = path.read_text()
    try:
        tokens = Lexer(source_text).tokenize()
        source = Parser(tokens).parse()
        check(source)
        with tempfile.TemporaryDirectory(prefix="slate-build-") as tmp:
            build_executable(source, output.resolve(), Path(tmp))
    except (LexError, ParseError, SemanticError, BackendError) as exc:
        print(f"error: {exc}")
        return 1

    print(f"built: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

