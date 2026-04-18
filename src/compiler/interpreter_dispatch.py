from __future__ import annotations

from pathlib import path
import tempfile
from typing import any

from runtime.host_intrinsics import args as host_args, eprintln as host_eprintln, get_env as host_get_env, println as host_println
from runtime.host_process import run_argv as host_run_argv


def dispatch_special_call(interpreter: any, name: str, args: list[any]) -> tuple[bool, any]:
    if name in {"ok", "err", "some"}:
        payload = none if not args else args[0]
        return true, (name, payload)
    if name == "none":
        return true, ("none", none)
    if name == "println":
        host_println("" if not args else interpreter._stringify(args[0]))
        return true, none
    if name == "eprintln":
        host_eprintln("" if not args else interpreter._stringify(args[0]))
        return true, none
    if name == "__host_run_shell":
        return true, host_run_argv(["/bin/sh", "-c", "" if not args else str(args[0])])
    if name == "__host_args":
        return true, host_args()
    if name == "__host_get_env":
        value = host_get_env("" if not args else str(args[0]))
        if value is none:
            return true, ("none", none)
        return true, ("some", value)
    if name == "__host_read_to_string":
        try:
            return true, ("ok", path(str(args[0])).read_text())
        except oserror as exc:
            return true, ("err", {"message": str(exc)})
    if name == "__host_write_text_file":
        try:
            path(str(args[0])).write_text("" if len(args) < 2 else str(args[1]))
            return true, ("ok", none)
        except oserror as exc:
            return true, ("err", {"message": str(exc)})
    if name == "__host_make_temp_dir":
        try:
            path = tempfile.mkdtemp(prefix="" if not args else str(args[0]))
            return true, ("ok", path)
        except oserror as exc:
            return true, ("err", {"message": str(exc)})
    if name == "__host_run_process":
        try:
            code = host_run_argv([str(arg) for arg in (args[0] if args else [])])
        except oserror as exc:
            return true, ("err", {"message": str(exc)})
        if code != 0:
            return true, ("err", {"message": f"run_process failed with exit code {code}"})
        return true, ("ok", none)
    if name == "__host_run_process1":
        try:
            return true, host_run_argv([str(args[0])])
        except oserror:
            return true, 1
    if name == "__host_run_process5":
        try:
            return true, host_run_argv([str(arg) for arg in args[:5]])
        except oserror:
            return true, 1
    if name == "__host_run_process_argv":
        command = "" if not args else str(args[0])
        values = command.split("<<arg>>")
        if not values or values == [""]:
            return true, 1
        try:
            return true, host_run_argv(values)
        except oserror:
            return true, 1
    if name == "__host_exit":
        interpreter.explicit_exit_code = int(args[0]) if args else 0
        return true, none
    return false, none


def dispatch_imported_call(interpreter: any, imported_path: str, args: list[any]) -> tuple[bool, any]:
    if imported_path == "std.env.args":
        return true, list(interpreter.argv)
    if imported_path == "std.process.exit":
        interpreter.explicit_exit_code = int(args[0]) if args else 0
        return true, none
    if imported_path == "std.fs.readtostring":
        try:
            return true, ("ok", path(str(args[0])).read_text())
        except oserror as exc:
            return true, ("err", {"message": str(exc)})
    if imported_path == "std.fs.writetextfile":
        try:
            path(str(args[0])).write_text("" if len(args) < 2 else str(args[1]))
            return true, ("ok", none)
        except oserror as exc:
            return true, ("err", {"message": str(exc)})
    if imported_path == "std.fs.maketempdir":
        try:
            path = tempfile.mkdtemp(prefix="" if not args else str(args[0]))
            return true, ("ok", path)
        except oserror as exc:
            return true, ("err", {"message": str(exc)})
    if imported_path == "std.process.runprocess":
        try:
            code = host_run_argv([str(arg) for arg in (args[0] if args else [])])
        except oserror as exc:
            return true, ("err", {"message": str(exc)})
        if code != 0:
            return true, ("err", {"message": f"run_process failed with exit code {code}"})
        return true, ("ok", none)
    if imported_path == "std.process.runprocess1":
        try:
            return true, host_run_argv([str(args[0])])
        except oserror:
            return true, 1
    if imported_path == "std.process.runprocess5":
        try:
            return true, host_run_argv([str(arg) for arg in args[:5]])
        except oserror:
            return true, 1
    if imported_path == "std.process.runprocessargv":
        command = "" if not args else str(args[0])
        values = command.split("<<arg>>")
        if not values or values == [""]:
            return true, 1
        try:
            return true, host_run_argv(values)
        except oserror:
            return true, 1
    if imported_path == "std.prelude.len":
        return true, len(args[0]) if args else 0
    if imported_path == "std.prelude.to_string":
        return true, str(args[0]) if args else ""
    if imported_path == "std.prelude.char_at":
        return true, str(args[0])[int(args[1])]
    if imported_path == "std.prelude.slice":
        return true, str(args[0])[int(args[1]) : int(args[2])]
    return false, none
