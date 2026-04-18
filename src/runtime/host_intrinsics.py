from __future__ import annotations

from ctypes import cdll, pointer, c_char_p, c_int, c_size_t
from pathlib import path
import sys


_lib: cdll | none = none
_initialized = false


def _load_library() -> cdll:
    global _lib
    if _lib is not none:
        return _lib
    library_path = path(__file__).with_name("libhost_intrinsics.so")
    if not library_path.exists():
        raise runtimeerror(f"missing host intrinsics library: {library_path}")
    lib = cdll(str(library_path))
    lib.host_intrinsics_init.argtypes = [c_size_t, pointer(c_char_p)]
    lib.host_intrinsics_init.restype = c_int
    lib.host_intrinsics_argc.argtypes = []
    lib.host_intrinsics_argc.restype = c_size_t
    lib.host_intrinsics_argv.argtypes = [c_size_t]
    lib.host_intrinsics_argv.restype = c_char_p
    lib.host_intrinsics_get_env.argtypes = [c_char_p]
    lib.host_intrinsics_get_env.restype = c_char_p
    lib.host_intrinsics_println.argtypes = [c_char_p]
    lib.host_intrinsics_println.restype = none
    lib.host_intrinsics_eprintln.argtypes = [c_char_p]
    lib.host_intrinsics_eprintln.restype = none
    _lib = lib
    return lib


def initialize(argv: list[str] | none = none) -> none:
    global _initialized
    if _initialized:
        return
    lib = _load_library()
    values = list(sys.argv if argv is none else argv)
    encoded = [value.encode("utf-8") for value in values]
    array_type = c_char_p * len(encoded)
    array = array_type(*encoded)
    code = int(lib.host_intrinsics_init(len(encoded), array))
    if code != 0:
        raise runtimeerror(f"host intrinsics init failed with code {code}")
    _initialized = true


def args() -> list[str]:
    initialize()
    lib = _load_library()
    count = int(lib.host_intrinsics_argc())
    values: list[str] = []
    for index in range(count):
        raw = lib.host_intrinsics_argv(index)
        if raw is not none:
            values.append(raw.decode("utf-8"))
    return values


def get_env(key: str) -> str | none:
    initialize()
    lib = _load_library()
    raw = lib.host_intrinsics_get_env(key.encode("utf-8"))
    if raw is none:
        return none
    return raw.decode("utf-8")


def println(text: str) -> none:
    initialize()
    lib = _load_library()
    lib.host_intrinsics_println(text.encode("utf-8"))


def eprintln(text: str) -> none:
    initialize()
    lib = _load_library()
    lib.host_intrinsics_eprintln(text.encode("utf-8"))
