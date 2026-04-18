from __future__ import annotations

from ctypes import cdll, c_char_p, c_int, c_void_p
from pathlib import Path


_lib: cdll | None = None


def _load_library() -> cdll:
    global _lib
    if _lib is not None:
        return _lib
    library_path = Path(__file__).with_name("libhost_fs.so")
    if not library_path.exists():
        raise RuntimeError(f"missing host fs library: {library_path}")
    lib = cdll(str(library_path))
    lib.host_fs_free.argtypes = [c_void_p]
    lib.host_fs_free.restype = None
    lib.host_fs_read_to_string.argtypes = [c_char_p]
    lib.host_fs_read_to_string.restype = c_void_p
    lib.host_fs_write_text_file.argtypes = [c_char_p, c_char_p]
    lib.host_fs_write_text_file.restype = c_int
    lib.host_fs_make_temp_dir.argtypes = [c_char_p, c_char_p]
    lib.host_fs_make_temp_dir.restype = c_void_p
    _lib = lib
    return lib


def _take_string(ptr: int) -> str:
    if not ptr:
        raise RuntimeError("host fs returned null")
    lib = _load_library()
    try:
        from ctypes import string_at

        return string_at(ptr).decode("utf-8")
    finally:
        lib.host_fs_free(c_void_p(ptr))


def read_to_string(path: str) -> str:
    lib = _load_library()
    return _take_string(int(lib.host_fs_read_to_string(path.encode("utf-8"))))


def write_text_file(path: str, contents: str) -> None:
    lib = _load_library()
    code = int(lib.host_fs_write_text_file(path.encode("utf-8"), contents.encode("utf-8")))
    if code != 0:
        raise RuntimeError(f"write_text_file failed for {path}")


def make_temp_dir(prefix: str, base_dir: str = "/app/tmp") -> str:
    lib = _load_library()
    return _take_string(int(lib.host_fs_make_temp_dir(prefix.encode("utf-8"), base_dir.encode("utf-8"))))
