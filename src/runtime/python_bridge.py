from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any, Callable, Generic, Iterable, TypeVar

BUILD_OUTPUT_ROOT = Path("/app/tmp")


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
        return len(value)
    if isinstance(value, HostArray):
        return len(value.storage)
    if hasattr(value, "length"):
        return int(getattr(value, "length"))
    if hasattr(value, "__len__"):
        return len(value)  # type: ignore[arg-type]
    raise RuntimeTrap(f"len unsupported for {type(value).__name__}")


def __int_to_string(value: int) -> str:
    return str(value)


def __string_concat(left: str, right: str) -> str:
    return left + right


def __string_replace(text: str, old: str, new: str) -> str:
    return text.replace(old, new)


def __string_char_at(text: str, index: int) -> str:
    if index < 0 or index >= len(text):
        raise RuntimeTrap(f"string index out of bounds: {index}")
    return text[index]


def __string_slice(text: str, start: int, end: int) -> str:
    if start < 0 or end < start:
        raise RuntimeTrap(f"invalid string slice: {start}:{end}")
    if start > len(text):
        raise RuntimeTrap(f"invalid string slice: {start}:{end}")
    end = min(end, len(text))
    return text[start:end]


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
        return Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        raise RuntimeTrap(f"read_to_string failed for {path}: {exc}") from exc


def __host_write_text_file(path: str, contents: str) -> None:
    try:
        target = Path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents, encoding="utf-8")
    except OSError as exc:
        raise RuntimeTrap(f"write_text_file failed for {path}: {exc}") from exc


def __host_make_temp_dir(prefix: str) -> str:
    try:
        BUILD_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
        return tempfile.mkdtemp(prefix=prefix, dir=str(BUILD_OUTPUT_ROOT))
    except OSError as exc:
        raise RuntimeTrap(f"make_temp_dir failed for {prefix}: {exc}") from exc


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
    raise RuntimeTrap(f"run_process expected Vec[String]-like argv, got {type(argv).__name__}")


def __host_run_process(argv: object) -> None:
    args = _coerce_argv(argv)
    if not args:
        raise RuntimeTrap("run_process expected at least one argv entry")
    try:
        subprocess.run(args, check=True, capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise RuntimeTrap(f"run_process failed, command not found: {args[0]}") from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip() if exc.stderr else ""
        detail = f": {stderr}" if stderr else ""
        raise RuntimeTrap(
            f"run_process failed with exit code {exc.returncode}{detail}"
        ) from exc


def __host_args() -> list[str]:
    return list(sys.argv[1:])


def __host_get_env(key: str) -> str | None:
    return os.environ.get(key)


def __host_exit(code: int) -> None:
    raise RuntimeExit(int(code))


def __host_println(text: str) -> None:
    print(text)


def __host_eprintln(text: str) -> None:
    print(text, file=sys.stderr)


def __option_panic_unwrap() -> object:
    raise RuntimeTrap("called Option.unwrap() on None")


def __result_panic_unwrap() -> object:
    raise RuntimeTrap("called Result.unwrap() on Err")


def __result_panic_unwrap_err() -> object:
    raise RuntimeTrap("called Result.unwrap_err() on Ok")


_LOCAL_INTRINSICS: dict[str, IntrinsicSpec] = {
    "__runtime_len": IntrinsicSpec("__runtime_len", __runtime_len, 1, "i32"),
    "__int_to_string": IntrinsicSpec("__int_to_string", __int_to_string, 1, "String"),
    "__string_concat": IntrinsicSpec("__string_concat", __string_concat, 2, "String"),
    "__string_replace": IntrinsicSpec("__string_replace", __string_replace, 3, "String"),
    "__string_char_at": IntrinsicSpec("__string_char_at", __string_char_at, 2, "String"),
    "__string_slice": IntrinsicSpec("__string_slice", __string_slice, 3, "String"),
    "__vec_new_array": IntrinsicSpec("__vec_new_array", __vec_new_array, 1, "Array[T]"),
    "__vec_array_get": IntrinsicSpec("__vec_array_get", __vec_array_get, 2, "T"),
    "__vec_array_set": IntrinsicSpec("__vec_array_set", __vec_array_set, 3, "()"),
    "__host_read_to_string": IntrinsicSpec(
        "__host_read_to_string",
        __host_read_to_string,
        1,
        "String",
        "bridge success path returns payload; host failures raise RuntimeTrap",
    ),
    "__host_write_text_file": IntrinsicSpec(
        "__host_write_text_file",
        __host_write_text_file,
        2,
        "()",
        "bridge success path returns unit; host failures raise RuntimeTrap",
    ),
    "__host_make_temp_dir": IntrinsicSpec(
        "__host_make_temp_dir",
        __host_make_temp_dir,
        1,
        "String",
        "bridge success path returns payload; host failures raise RuntimeTrap",
    ),
    "__host_run_process": IntrinsicSpec(
        "__host_run_process",
        __host_run_process,
        1,
        "()",
        "bridge success path returns unit; host failures raise RuntimeTrap",
    ),
    "__host_args": IntrinsicSpec(
        "__host_args",
        __host_args,
        0,
        "Vec[String]",
        "bridge success path returns argv without the executable name",
    ),
    "__host_get_env": IntrinsicSpec(
        "__host_get_env",
        __host_get_env,
        1,
        "Option[String]",
        "bridge success path returns environment values when present",
    ),
    "__host_exit": IntrinsicSpec(
        "__host_exit",
        __host_exit,
        1,
        "never",
        "host process termination boundary for S command wrappers",
    ),
    "__host_println": IntrinsicSpec("__host_println", __host_println, 1, "()"),
    "__host_eprintln": IntrinsicSpec("__host_eprintln", __host_eprintln, 1, "()"),
    "__option_panic_unwrap": IntrinsicSpec("__option_panic_unwrap", __option_panic_unwrap, 0, "never"),
    "__result_panic_unwrap": IntrinsicSpec("__result_panic_unwrap", __result_panic_unwrap, 0, "never"),
    "__result_panic_unwrap_err": IntrinsicSpec("__result_panic_unwrap_err", __result_panic_unwrap_err, 0, "never"),
}


def _load_manifest() -> dict[str, IntrinsicSpec]:
    manifest_path = Path(__file__).with_name("intrinsics_manifest.json")
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest_specs: dict[str, IntrinsicSpec] = {}
    for item in data["intrinsics"]:
        name = item["name"]
        func = _LOCAL_INTRINSICS.get(name)
        if func is None:
            raise RuntimeTrap(f"manifest declares intrinsic without bridge implementation: {name}")
        manifest_specs[name] = IntrinsicSpec(
            name=name,
            func=func.func,
            arity=int(item["arity"]),
            returns=item["returns"],
            notes=item.get("notes", ""),
        )
    return manifest_specs


def _validate_manifest(manifest_specs: dict[str, IntrinsicSpec]) -> None:
    local_names = set(_LOCAL_INTRINSICS)
    manifest_names = set(manifest_specs)
    missing = sorted(local_names - manifest_names)
    if missing:
        raise RuntimeTrap(
            "local bridge intrinsics missing from manifest: " + ", ".join(missing)
        )
    for name, spec in manifest_specs.items():
        local = _LOCAL_INTRINSICS[name]
        if local.arity != spec.arity:
            raise RuntimeTrap(
                f"manifest arity mismatch for {name}: local={local.arity} manifest={spec.arity}"
            )
        if local.returns != spec.returns:
            raise RuntimeTrap(
                f"manifest return mismatch for {name}: local={local.returns} manifest={spec.returns}"
            )


INTRINSICS = _load_manifest()
_validate_manifest(INTRINSICS)


def get_intrinsic(name: str) -> IntrinsicSpec:
    try:
        return INTRINSICS[name]
    except KeyError as exc:
        raise RuntimeTrap(f"unknown intrinsic {name}") from exc


def invoke_intrinsic(name: str, *args: Any) -> Any:
    spec = get_intrinsic(name)
    if len(args) != spec.arity:
        raise RuntimeTrap(
            f"intrinsic {name} expected {spec.arity} args, got {len(args)}"
        )
    return spec.func(*args)


def list_intrinsics() -> Iterable[str]:
    return sorted(INTRINSICS)


def list_specs() -> list[IntrinsicSpec]:
    return [INTRINSICS[name] for name in list_intrinsics()]
