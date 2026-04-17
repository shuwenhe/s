from __future__ import annotations

import argparse

from compiler.hosted_compiler import run_cli


def main(argv: list[str] | None = None)  int:
    parser = argparse.ArgumentParser(prog="s")
    sub = parser.add_subparsers(dest="command", required=True)

    check_cmd = sub.add_parser("check", help="parse and type-check an S source file")
    check_cmd.add_argument("path")
    check_cmd.add_argument("--dump-tokens", action="store_true")
    check_cmd.add_argument("--dump-ast", action="store_true")

    build_cmd = sub.add_parser("build", help="build a minimal S source file into a native binary")
    build_cmd.add_argument("path")
    build_cmd.add_argument("-o", "--output", required=True)

    run_cmd = sub.add_parser("run", help="interpret a minimal S source file")
    run_cmd.add_argument("path")

    args = parser.parse_args(argv)
    if args.command == "check":
        cmd = [args.command, args.path]
        if args.dump_tokens:
            cmd.append("--dump-tokens")
        if args.dump_ast:
            cmd.append("--dump-ast")
        return run_cli(cmd)
    if args.command == "build":
        return run_cli([args.command, args.path, "-o", args.output])
    if args.command == "run":
        return run_cli([args.command, args.path])
    parser.error("unknown command")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
