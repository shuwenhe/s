from __future__ import annotations

from dataclasses import dataclass
from typing import Generic, Iterable, TypeVar


T = TypeVar("T")


class RuntimeTrap(RuntimeError):
    pass


@dataclass
class HostArray(Generic[T]):
    storage: list[T | None]


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


def __string_char_at(text: str, index: int) -> str:
    if index < 0 or index >= len(text):
        raise RuntimeTrap(f"string index out of bounds: {index}")
    return text[index]


def __string_slice(text: str, start: int, end: int) -> str:
    if start < 0 or end < start or end > len(text):
        raise RuntimeTrap(f"invalid string slice: {start}:{end}")
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


def __option_panic_unwrap() -> object:
    raise RuntimeTrap("called Option.unwrap() on None")


def __result_panic_unwrap() -> object:
    raise RuntimeTrap("called Result.unwrap() on Err")


def __result_panic_unwrap_err() -> object:
    raise RuntimeTrap("called Result.unwrap_err() on Ok")


INTRINSICS = {
    "__runtime_len": __runtime_len,
    "__int_to_string": __int_to_string,
    "__string_char_at": __string_char_at,
    "__string_slice": __string_slice,
    "__vec_new_array": __vec_new_array,
    "__vec_array_get": __vec_array_get,
    "__vec_array_set": __vec_array_set,
    "__option_panic_unwrap": __option_panic_unwrap,
    "__result_panic_unwrap": __result_panic_unwrap,
    "__result_panic_unwrap_err": __result_panic_unwrap_err,
}


def get_intrinsic(name: str):
    try:
        return INTRINSICS[name]
    except KeyError as exc:
        raise RuntimeTrap(f"unknown intrinsic {name}") from exc


def list_intrinsics() -> Iterable[str]:
    return sorted(INTRINSICS)
