from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Generic, TypeVar

from runtime.host_fs import make_temp_dir as host_make_temp_dir, read_to_string as host_read_to_string, write_text_file as host_write_text_file
from runtime.host_intrinsics import args as host_args, eprintln as host_eprintln, get_env as host_get_env, println as host_println
from runtime.host_process import run_argv as host_run_argv
from compiler.backend_elf64 import backenderror, build_executable
from compiler.hosted_compiler import resolve_output_path
from compiler.parser import parseerror, parse_source
from compiler.semantic import check_source
from runtime.intrinsics_core import int_to_string, string_char_at, string_concat, string_len, string_replace, string_slice

build_output_root = path("/tmp/s-runtime")


t = typevar("t")


class runtimetrap(runtimeerror):
    pass


@dataclass(frozen=true)
class runtimeexit(runtimeerror):
    code: int

    def __str__(self) -> str:
        return f"process exited with code {self.code}"


@dataclass
class hostarray(generic[t]):
    storage: list[t | none]


@dataclass(frozen=true)
class intrinsicspec:
    name: str
    func: callable[..., any]
    arity: int
    returns: str
    notes: str = ""


def __runtime_len(value: object) -> int:
    if isinstance(value, str):
        return string_len(value)
    if isinstance(value, hostarray):
        return len(value.storage)
    if hasattr(value, "length"):
        return int(getattr(value, "length"))
    if hasattr(value, "__len__"):
        return len(value)  # type: ignore[arg-type]
    raise runtimetrap(f"len unsupported for {type(value).__name__}")


def __int_to_string(value: int) -> str:
    try:
        return int_to_string(value)
    except runtimeerror as exc:
        raise runtimetrap(f"int_to_string failed for {value}") from exc


def __string_concat(left: str, right: str) -> str:
    try:
        return string_concat(left, right)
    except runtimeerror as exc:
        raise runtimetrap("string concat failed") from exc


def __string_replace(text: str, old: str, new: str) -> str:
    try:
        return string_replace(text, old, new)
    except runtimeerror as exc:
        raise runtimetrap("string replace failed") from exc


def __string_char_at(text: str, index: int) -> str:
    try:
        return string_char_at(text, index)
    except runtimeerror as exc:
        raise runtimetrap(f"string index out of bounds: {index}") from exc


def __string_slice(text: str, start: int, end: int) -> str:
    try:
        return string_slice(text, start, end)
    except runtimeerror as exc:
        raise runtimetrap(f"invalid string slice: {start}:{end}") from exc


def __vec_new_array(size: int) -> hostarray[object]:
    if size < 0:
        raise runtimetrap(f"negative array size: {size}")
    return hostarray([none for _ in range(size)])


def __vec_array_get(array: hostarray[t], index: int) -> t:
    if index < 0 or index >= len(array.storage):
        raise runtimetrap(f"array index out of bounds: {index}")
    value = array.storage[index]
    if value is none:
        raise runtimetrap(f"read before initialization at index {index}")
    return value


def __vec_array_set(array: hostarray[t], index: int, value: t) -> none:
    if index < 0 or index >= len(array.storage):
        raise runtimetrap(f"array index out of bounds: {index}")
    array.storage[index] = value


def __host_read_to_string(path: str) -> str:
    try:
        return host_read_to_string(path)
    except runtimeerror as exc:
        raise runtimetrap(f"read_to_string failed for {path}: {exc}") from exc


def __host_write_text_file(path: str, contents: str) -> none:
    try:
        host_write_text_file(path, contents)
    except runtimeerror as exc:
        raise runtimetrap(f"write_text_file failed for {path}: {exc}") from exc


def __host_make_temp_dir(prefix: str) -> str:
    try:
        build_output_root.mkdir(parents=true, exist_ok=true)
        return host_make_temp_dir(prefix, str(build_output_root))
    except runtimeerror as exc:
        raise runtimetrap(f"make_temp_dir failed for {prefix}: {exc}") from exc


def __host_build_executable(path: str, output: str) -> int:
    try:
        source = path(path).read_text()
        parsed = parse_source(source)
        result = check_source(parsed)
        if not result.ok:
            raise runtimetrap("semantic check failed")
        build_executable(parsed, resolve_output_path(output))
        return 0
    except (parseerror, runtimeerror, backenderror) as exc:
        raise runtimetrap(f"build_executable failed for {path}: {exc}") from exc


def _coerce_argv(argv: object) -> list[str]:
    if isinstance(argv, hostarray):
        values: list[str] = []
        for value in argv.storage:
            if value is none:
                continue
            values.append(str(value))
        return values
    if isinstance(argv, (list, tuple)):
        return [str(value) for value in argv]
    raise runtimetrap(f"run_process expected vec[string]-like argv, got {type(argv).__name__}")


def __host_run_process(argv: object) -> none:
    args = _coerce_argv(argv)
    if not args:
        raise runtimetrap("run_process expected at least one argv entry")
    code = host_run_argv(args)
    if code != 0:
        raise runtimetrap(f"run_process failed with exit code {code}")


def __host_run_process1(program: str) -> int:
    return host_run_argv([program])


def __host_run_process5(program: str, arg1: str, arg2: str, arg3: str, arg4: str) -> int:
    return host_run_argv([program, arg1, arg2, arg3, arg4])


def __host_run_process_argv(encoded: str) -> int:
    args = encoded.split("<<arg>>")
    if not args or args == [""]:
        raise runtimetrap("run_process expected at least one argv entry")
    return host_run_argv(args)


def __host_run_shell(command: str) -> int:
    return host_run_argv(["/bin/sh", "-c", command])


def __host_args() -> list[str]:
    return host_args()


def __host_get_env(key: str) -> str | none:
    return host_get_env(key)


def __host_exit(code: int) -> none:
    raise runtimeexit(int(code))


def __host_println(text: str) -> none:
    host_println(text)


def __host_eprintln(text: str) -> none:
    host_eprintln(text)


def __option_panic_unwrap() -> object:
    raise runtimetrap("called option.unwrap() on none")


def __result_panic_unwrap() -> object:
    raise runtimetrap("called result.unwrap() on err")


def __result_panic_unwrap_err() -> object:
    raise runtimetrap("called result.unwrap_err() on ok")
