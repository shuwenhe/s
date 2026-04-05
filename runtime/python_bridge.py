from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import inspect
from typing import Any, Callable, Generic, Iterable, TypeVar


T = TypeVar("T")


class RuntimeTrap(RuntimeError):
    pass


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
    return Path(path).read_text()


def __host_println(text: str) -> str:
    return text


def __host_eprintln(text: str) -> str:
    return text


def __option_panic_unwrap() -> object:
    raise RuntimeTrap("called Option.unwrap() on None")


def __result_panic_unwrap() -> object:
    raise RuntimeTrap("called Result.unwrap() on Err")


def __result_panic_unwrap_err() -> object:
    raise RuntimeTrap("called Result.unwrap_err() on Ok")


INTRINSICS: dict[str, IntrinsicSpec] = {
    "__runtime_len": IntrinsicSpec("__runtime_len", __runtime_len, 1, "i32"),
    "__int_to_string": IntrinsicSpec("__int_to_string", __int_to_string, 1, "String"),
    "__string_concat": IntrinsicSpec("__string_concat", __string_concat, 2, "String"),
    "__string_replace": IntrinsicSpec("__string_replace", __string_replace, 3, "String"),
    "__string_char_at": IntrinsicSpec("__string_char_at", __string_char_at, 2, "String"),
    "__string_slice": IntrinsicSpec("__string_slice", __string_slice, 3, "String"),
    "__vec_new_array": IntrinsicSpec("__vec_new_array", __vec_new_array, 1, "Array[T]"),
    "__vec_array_get": IntrinsicSpec("__vec_array_get", __vec_array_get, 2, "T"),
    "__vec_array_set": IntrinsicSpec("__vec_array_set", __vec_array_set, 3, "()"),
    "__host_read_to_string": IntrinsicSpec("__host_read_to_string", __host_read_to_string, 1, "String"),
    "__host_println": IntrinsicSpec("__host_println", __host_println, 1, "String"),
    "__host_eprintln": IntrinsicSpec("__host_eprintln", __host_eprintln, 1, "String"),
    "__option_panic_unwrap": IntrinsicSpec("__option_panic_unwrap", __option_panic_unwrap, 0, "never"),
    "__result_panic_unwrap": IntrinsicSpec("__result_panic_unwrap", __result_panic_unwrap, 0, "never"),
    "__result_panic_unwrap_err": IntrinsicSpec("__result_panic_unwrap_err", __result_panic_unwrap_err, 0, "never"),
}


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
