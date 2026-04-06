from __future__ import annotations

from pathlib import Path
import os
import stat
import sys


LAUNCHER = """#!/usr/bin/env python3
from pathlib import Path
import sys

sys.path.insert(0, "/app/s")

from compiler.interpreter import Interpreter, InterpreterError
from compiler.parser import ParseError, parse_source


def main() -> int:
    try:
        source = Path("/app/s/runtime/runner.s").read_text()
        runner = Interpreter(parse_source(source))
        runner.argv = sys.argv[1:]
        return int(runner.run_main())
    except (OSError, ParseError, InterpreterError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
"""


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: write_s_native_launcher.py <output>", file=sys.stderr)
        return 1
    output = Path(argv[1]).resolve()
    output.write_text(LAUNCHER)
    mode = output.stat().st_mode
    output.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
