from __future__ import annotations

from ctypes import cdll, c_char_p, c_longlong, c_size_t, c_void_p, string_at
from pathlib import Path


_lib: cdll | none = none


def _load_library() -> cdll:
    global _lib
    if _lib is not none:
        return _lib
    library_path = path(__file__).with_name("libintrinsics_core.so")
    if not library_path.exists():
        raise runtimeerror(f"missing intrinsic core library: {library_path}")
    lib = cdll(str(library_path))
    lib.intrinsics_core_free.argtypes = [c_void_p]
    lib.intrinsics_core_free.restype = none
    lib.intrinsics_core_string_len.argtypes = [c_char_p]
    lib.intrinsics_core_string_len.restype = c_size_t
    lib.intrinsics_core_int_to_string.argtypes = [c_longlong]
    lib.intrinsics_core_int_to_string.restype = c_void_p
    lib.intrinsics_core_string_concat.argtypes = [c_char_p, c_char_p]
    lib.intrinsics_core_string_concat.restype = c_void_p
    lib.intrinsics_core_string_replace.argtypes = [c_char_p, c_char_p, c_char_p]
    lib.intrinsics_core_string_replace.restype = c_void_p
    lib.intrinsics_core_string_char_at.argtypes = [c_char_p, c_longlong]
    lib.intrinsics_core_string_char_at.restype = c_void_p
    lib.intrinsics_core_string_slice.argtypes = [c_char_p, c_longlong, c_longlong]
    lib.intrinsics_core_string_slice.restype = c_void_p
    _lib = lib
    return lib


def _take_string(ptr: int) -> str:
    if not ptr:
        raise runtimeerror("intrinsic core returned null")
    lib = _load_library()
    try:
        data = string_at(ptr)
        return data.decode("utf-8")
    finally:
        lib.intrinsics_core_free(c_void_p(ptr))


def string_len(text: str) -> int:
    lib = _load_library()
    return int(lib.intrinsics_core_string_len(text.encode("utf-8")))


def int_to_string(value: int) -> str:
    lib = _load_library()
    return _take_string(int(lib.intrinsics_core_int_to_string(int(value))))


def string_concat(left: str, right: str) -> str:
    lib = _load_library()
    return _take_string(int(lib.intrinsics_core_string_concat(left.encode("utf-8"), right.encode("utf-8"))))


def string_replace(text: str, old: str, new: str) -> str:
    lib = _load_library()
    return _take_string(
        int(lib.intrinsics_core_string_replace(text.encode("utf-8"), old.encode("utf-8"), new.encode("utf-8")))
    )


def string_char_at(text: str, index: int) -> str:
    lib = _load_library()
    return _take_string(int(lib.intrinsics_core_string_char_at(text.encode("utf-8"), int(index))))


def string_slice(text: str, start: int, end: int) -> str:
    lib = _load_library()
    return _take_string(int(lib.intrinsics_core_string_slice(text.encode("utf-8"), int(start), int(end))))
