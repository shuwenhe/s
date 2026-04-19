from __future__ import annotations

from ctypes import CDLL, POINTER, c_char_p, c_int, c_size_t
from pathlib import Path


_lib: CDLL | None = None


def _load_library() -> CDLL:
    global _lib
    if _lib is not None:
        return _lib
    library_path = Path(__file__).with_name("libhost_process.so")
    if not library_path.exists():
        raise RuntimeError(f"missing host process library: {library_path}")
    lib = CDLL(str(library_path))
    lib.host_process_run_argv.argtypes = [c_size_t, POINTER(c_char_p)]
    lib.host_process_run_argv.restype = c_int
    _lib = lib
    return lib


def run_argv(argv: list[str]) -> int:
    lib = _load_library()
    encoded = [arg.encode("utf-8") for arg in argv]
    array_type = c_char_p * (len(encoded) + 1)
    array = array_type(*encoded, None)
    return int(lib.host_process_run_argv(len(encoded), array))
