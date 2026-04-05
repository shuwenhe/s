from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.ast import dump_source_file
from compiler.lexer import Lexer, dump_tokens
from compiler.parser import parse_source


FIXTURES = ROOT / "compiler" / "tests" / "fixtures"


def validate_lex() -> bool:
    source = (FIXTURES / "sample.s").read_text()
    expected = (FIXTURES / "sample.tokens").read_text().strip()
    actual = dump_tokens(Lexer(source).tokenize()).strip()
    return report_case("lex_dump", expected, actual)


def validate_ast() -> bool:
    source = (FIXTURES / "sample.s").read_text()
    expected = (FIXTURES / "sample.ast").read_text().strip()
    actual = dump_source_file(parse_source(source)).strip()
    return report_case("ast_dump", expected, actual)


def report_case(name: str, expected: str, actual: str) -> bool:
    if expected == actual:
        print(f"[ok] {name}")
        return True
    print(f"[fail] {name}", file=sys.stderr)
    print("--- expected ---", file=sys.stderr)
    print(expected, file=sys.stderr)
    print("--- actual ---", file=sys.stderr)
    print(actual, file=sys.stderr)
    return False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="validate_outputs")
    parser.add_argument(
        "target",
        choices=["lex", "ast", "all"],
        default="all",
        nargs="?",
        help="which hosted output contract to validate",
    )
    args = parser.parse_args(argv)

    checks: list[bool] = []
    if args.target in {"lex", "all"}:
        checks.append(validate_lex())
    if args.target in {"ast", "all"}:
        checks.append(validate_ast())
    return 0 if all(checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
