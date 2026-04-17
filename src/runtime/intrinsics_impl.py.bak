from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Generic, TypeVar

from runtime.host_fs import make_temp_dir as host_make_temp_dir, read_to_string as host_read_to_string, write_text_file as host_write_text_file
from runtime.host_intrinsics import args as host_args, eprintln as host_eprintln, get_env as host_get_env, println as host_println
from runtime.host_process import run_argv as host_run_argv
from compiler.backend_elf64 import BackendError, build_executable
from compiler.hosted_compiler import resolve_output_path
from compiler.parser import ParseError, parse_source
from compiler.semantic import check_source
from runtime.intrinsics_core import int_to_string, string_char_at, string_concat, string_len, string_replace, string_slice

BUILD_OUTPUT_ROOT = Path("/tmp/s-runtime")


T = TypeVar("T")


class RuntimeTrap(RuntimeError):
    pass


@dataclass(frozen=True)
class RuntimeExit(RuntimeError):
    code: int

    def __str__(self) -> str:
        return f"process exited with code {self.code}"


@dataclass
class HostArray(Generic[T]):
    storage: list[T | None]


@dataclass(frozen=True)
class IntrinsicSpec:
    name: str
    func: Callable[..., Any]
    arity: int
    returns: str
    notes: str = ""


def __runtime_len(value: object) -> int:
    if isinstance(value, str):
        return string_len(value)
    if isinstance(value, HostArray):
        return len(value.storage)
    if hasattr(value, "length"):
        return int(getattr(value, "length"))
    if hasattr(value, "__len__"):
        return len(value)  # type: ignore[arg-type]
    raise RuntimeTrap(f"len unsupported for {type(value).__name__}")


def __int_to_string(value: int) -> str:
    try:
        return int_to_string(value)
    except RuntimeError as exc:
        raise RuntimeTrap(f"int_to_string failed for {value}") from exc


def __string_concat(left: str, right: str) -> str:
    try:
        return string_concat(left, right)
    except RuntimeError as exc:
        raise RuntimeTrap("string concat failed") from exc


def __string_replace(text: str, old: str, new: str) -> str:
    try:
        return string_replace(text, old, new)
    except RuntimeError as exc:
        raise RuntimeTrap("string replace failed") from exc


def __string_char_at(text: str, index: int) -> str:
    try:
        return string_char_at(text, index)
    except RuntimeError as exc:
        raise RuntimeTrap(f"string index out of bounds: {index}") from exc


def __string_slice(text: str, start: int, end: int) -> str:
    try:
        return string_slice(text, start, end)
    except RuntimeError as exc:
        raise RuntimeTrap(f"invalid string slice: {start}:{end}") from exc


def __vec_new_array(size: int) -> HostArray[object]:
    if size < 0:
        raise RuntimeTrap(f"negative array size: {size}")
    return HostArray([None for _ in range(size)])


def __vec_array_get(array: HostArray[T], index: int) -> T:
    if index < 0 or index >= len(array.storage):
        raise RuntimeTrap(f"array index out of bounds: {index}")
    value = array.storage[index]
    if value is None:
        raise RuntimeTrap(f"read before initialization at index {index}")
    return value


def __vec_array_set(array: HostArray[T], index: int, value: T) -> None:
    if index < 0 or index >= len(array.storage):
        raise RuntimeTrap(f"array index out of bounds: {index}")
    array.storage[index] = value


def __host_read_to_string(path: str) -> str:
    try:
        return host_read_to_string(path)
    except RuntimeError as exc:
        raise RuntimeTrap(f"read_to_string failed for {path}: {exc}") from exc


def __host_write_text_file(path: str, contents: str) -> None:
    try:
        host_write_text_file(path, contents)
    except RuntimeError as exc:
        raise RuntimeTrap(f"write_text_file failed for {path}: {exc}") from exc


def __host_make_temp_dir(prefix: str) -> str:
    try:
        BUILD_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
        return host_make_temp_dir(prefix, str(BUILD_OUTPUT_ROOT))
    except RuntimeError as exc:
        raise RuntimeTrap(f"make_temp_dir failed for {prefix}: {exc}") from exc


def __host_build_executable(path: str, output: str) -> int:
    try:
        source = Path(path).read_text()
        parsed = parse_source(source)
        result = check_source(parsed)
        if not result.ok:
            raise RuntimeTrap("semantic check failed")
        build_executable(parsed, resolve_output_path(output))
        return 0
    except (ParseError, RuntimeError, BackendError) as exc:
        raise RuntimeTrap(f"build_executable failed for {path}: {exc}") from exc


def _coerce_argv(argv: object) -> list[str]:
    if isinstance(argv, HostArray):
        values: list[str] = []
        for value in argv.storage:
            if value is None:
                continue
            values.append(str(value))
        return values
    if isinstance(argv, (list, tuple)):
        return [str(value) for value in argv]
    raise RuntimeTrap(f"run_process expected Vec[string]-like argv, got {type(argv).__name__}")


def __host_run_process(argv: object) -> None:
    args = _coerce_argv(argv)
    if not args:
        raise RuntimeTrap("run_process expected at least one argv entry")
    code = host_run_argv(args)
    if code != 0:
        raise RuntimeTrap(f"run_process failed with exit code {code}")


def __host_run_process1(program: str) -> int:
    return host_run_argv([program])


def __host_run_process5(program: str, arg1: str, arg2: str, arg3: str, arg4: str) -> int:
    return host_run_argv([program, arg1, arg2, arg3, arg4])


def __host_run_process_argv(encoded: str) -> int:
    args = encoded.split("<<ARG>>")
    if not args or args == [""]:
        raise RuntimeTrap("run_process expected at least one argv entry")
    return host_run_argv(args)


def __host_run_shell(command: str) -> int:
    return host_run_argv(["/bin/sh", "-c", command])


def __host_args() -> list[str]:
    return host_args()


def __host_get_env(key: str) -> str | None:
    return host_get_env(key)


def __host_exit(code: int) -> None:
    raise RuntimeExit(int(code))


def __host_println(text: str) -> None:
    host_println(text)


def __host_eprintln(text: str) -> None:
    host_eprintln(text)


def __option_panic_unwrap() -> object:
    raise RuntimeTrap("called Option.unwrap() on None")


def __result_panic_unwrap() -> object:
    raise RuntimeTrap("called Result.unwrap() on Err")


def __result_panic_unwrap_err() -> object:
    raise RuntimeTrap("called Result.unwrap_err() on Ok")
