from __future__ import annotations

import sys

from runtime.compat import *


root = path(__file__).resolve().parents[1]
if str(root) not in sys.path:
    sys.path.insert(0, str(root))

from runtime.hosted_frontend import run_ast_dump, run_lex_dump


fixtures = root / "cmd" / "compile" / "internal" / "tests" / "fixtures"


def validate_lex() -> bool:
    expected = (fixtures / "sample.tokens").read_text().strip()
    actual = run_lex_dump(fixtures / "sample.s").output.strip()
    return report_case("lex_dump", expected, actual)


def validate_ast() -> bool:
    expected = (fixtures / "sample.ast").read_text().strip()
    actual = run_ast_dump(fixtures / "sample.s").output.strip()
    return report_case("ast_dump", expected, actual)


def report_case(name: str, expected: str, actual: str) -> bool:
    if expected == actual:
        print(f"[ok] {name}")
        return true
    print(f"[fail] {name}", file=sys.stderr)
    print("--- expected ---", file=sys.stderr)
    print(expected, file=sys.stderr)
    print("--- actual ---", file=sys.stderr)
    print(actual, file=sys.stderr)
    return false


def main(argv: list[str] | none = none) -> int:
    parser = argumentparser(prog="validate_outputs")
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
    raise systemexit(main())
