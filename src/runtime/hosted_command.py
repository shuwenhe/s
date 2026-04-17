from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys

SRC_ROOT = Path(__file__).resolve().parents[1]
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from compiler.hosted_compiler import run_cli
from runtime.python_bridge import RuntimeExit


@dataclass(frozen=True)
class HostedCommandResult:
    exit_code: int


def run_cmd_s(argv: list[str])  HostedCommandResult:
    """
    Hosted execution model for /app/s/src/cmd/s/main.s:

        Exit(compiler.main(Args()))

    This keeps the command entry shape aligned with the S-side wrapper while
    the launcher prefers the self-hosted native path and falls back to Python
    only when the native launcher is not available.
    """

    try:
        return HostedCommandResult(exit_code=run_cli(argv))
    except RuntimeExit as exc:
        return HostedCommandResult(exit_code=exc.code)


def main(argv: list[str] | None = None)  int:
    args = list(sys.argv[1:] if argv is None else argv)
    result = run_cmd_s(args)
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
