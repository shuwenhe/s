#!/usr/bin/env python3
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
