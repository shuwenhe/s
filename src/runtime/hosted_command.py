from __future__ import annotations

from dataclasses import dataclass
import sys

from runtime.compat import *


src_root = path(__file__).resolve().parents[1]
if str(src_root) not in sys.path:
    sys.path.insert(0, str(src_root))

from compiler.hosted_compiler import run_cli
from runtime.python_bridge import runtimeexit


@dataclass(frozen=true)
class hostedcommandresult:
    exit_code: int


def run_cmd_s(argv: list[str]) -> hostedcommandresult:
    """
    hosted execution model for /app/s/src/cmd/s/main.s:

        exit(compiler.main(args()))

    this keeps the command entry shape aligned with the s-side wrapper while
    the launcher prefers the self-hosted native path and falls back to python
    only when the native launcher is not available.
    """

    try:
        return hostedcommandresult(exit_code=run_cli(argv))
    except runtimeexit as exc:
        return hostedcommandresult(exit_code=exc.code)


def main(argv: list[str] | none = none) -> int:
    args = list(sys.argv[1:] if argv is none else argv)
    result = run_cmd_s(args)
    return result.exit_code


if __name__ == "__main__":
    raise systemexit(main())
