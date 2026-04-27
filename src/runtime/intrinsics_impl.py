from __future__ import annotations


from runtime.compat import *
from runtime.host_fs import make_temp_dir as host_make_temp_dir, read_to_string as host_read_to_string, write_text_file as host_write_text_file
from runtime.host_intrinsics import args as host_args, eprintln as host_eprintln, get_env as host_get_env, println as host_println
from runtime.host_process import run_argv as host_run_argv
from runtime.intrinsics_core import int_to_string, string_char_at, string_concat, string_len, string_replace, string_slice


build_output_root = path("/tmp/s-runtime")
compiler_candidates = [
    "./bin/s-selfhosted",
    "/app/s/bin/s-selfhosted",
    "./bin/s-native",
    "/app/s/bin/s-native",
]



# S-only error signaling: use plain string error codes and None for normal returns
# S-only array: use plain list for hostarray

def s_trap(msg):
    raise Exception(f"S_TRAP: {msg}")

def s_exit(code):
    raise Exception(f"S_EXIT:{code}")


def __runtime_len(value: object) -> int:
    if isinstance(value, str):
        return string_len(value)
    if isinstance(value, list):
        return len(value)
    if hasattr(value, "length"):
        return int(getattr(value, "length"))
    if hasattr(value, "__len__"):
        return len(value)
    s_trap(f"len unsupported for {type(value).__name__}")


def __int_to_string(value: int) -> str:
    try:
        return int_to_string(value)
    except Exception:
        s_trap(f"int_to_string failed for {value}")


def __string_concat(left: str, right: str) -> str:
    try:
        return string_concat(left, right)
    except Exception:
        s_trap("string concat failed")


def __string_replace(text: str, old: str, new: str) -> str:
    try:
        return string_replace(text, old, new)
    except Exception:
        s_trap("string replace failed")


def __string_char_at(text: str, index: int) -> str:
    try:
        return string_char_at(text, index)
    except Exception:
        s_trap(f"string index out of bounds: {index}")


def __string_slice(text: str, start: int, end: int) -> str:
    try:
        return string_slice(text, start, end)
    except Exception:
        s_trap(f"invalid string slice: {start}:{end}")


def __vec_new_array(size: int) -> list:
    if size < 0:
        s_trap(f"negative array size: {size}")
    return [none for _ in range(size)]


def __vec_array_get(array: list, index: int):
    if index < 0 or index >= len(array):
        s_trap(f"array index out of bounds: {index}")
    value = array[index]
    if value is none:
        s_trap(f"read before initialization at index {index}")
    return value


def __vec_array_set(array: list, index: int, value):
    if index < 0 or index >= len(array):
        s_trap(f"array index out of bounds: {index}")
    array[index] = value


def __host_read_to_string(path: str) -> str:
    try:
        return host_read_to_string(path)
    except Exception as exc:
        s_trap(f"read_to_string failed for {path}: {exc}")


def __host_write_text_file(path: str, contents: str) -> none:
    try:
        host_write_text_file(path, contents)
    except Exception as exc:
        s_trap(f"write_text_file failed for {path}: {exc}")


def __host_make_temp_dir(prefix: str) -> str:
    try:
        build_output_root.mkdir(parents=true, exist_ok=true)
        return host_make_temp_dir(prefix, str(build_output_root))
    except Exception as exc:
        s_trap(f"make_temp_dir failed for {prefix}: {exc}")


def __host_build_executable(source_path: str, output: str) -> int:
    try:
        compiler = host_get_env("S_COMPILER")
        if compiler is none or compiler == "":
            for candidate in compiler_candidates:
                if path(candidate).exists():
                    compiler = candidate
                    break
        if compiler is none or compiler == "":
            s_trap("build_executable failed: no bootstrap compiler available")
        code = host_run_argv([str(compiler), "build", source_path, "-o", output])
        if code != 0:
            s_trap(f"build_executable failed for {source_path}: compiler exit code {code}")
        return 0
    except Exception as exc:
        s_trap(f"build_executable failed for {source_path}: {exc}")


def _coerce_argv(argv: object) -> list[str]:
    if isinstance(argv, list):
        return [str(value) for value in argv if value is not none]
    if isinstance(argv, tuple):
        return [str(value) for value in argv]
    s_trap(f"run_process expected vec[string]-like argv, got {type(argv).__name__}")


def __host_run_process(argv: object) -> none:
    args = _coerce_argv(argv)
    if not args:
        s_trap("run_process expected at least one argv entry")
    code = host_run_argv(args)
    if code != 0:
        s_trap(f"run_process failed with exit code {code}")


def __host_run_process1(program: str) -> int:
    return host_run_argv([program])


def __host_run_process5(program: str, arg1: str, arg2: str, arg3: str, arg4: str) -> int:
    return host_run_argv([program, arg1, arg2, arg3, arg4])


def __host_run_process_argv(encoded: str) -> int:
    args = encoded.split("<<arg>>")
    if not args or args == [""]:
        s_trap("run_process expected at least one argv entry")
    return host_run_argv(args)


def __host_run_shell(command: str) -> int:
    return host_run_argv(["/bin/sh", "-c", command])


def __host_args() -> list[str]:
    return host_args()


def __host_get_env(key: str) -> str | none:
    return host_get_env(key)


def __host_exit(code: int) -> none:
    s_exit(int(code))


def __host_println(text: str) -> none:
    host_println(text)


def __host_eprintln(text: str) -> none:
    host_eprintln(text)


def __option_panic_unwrap() -> object:
    s_trap("called option.unwrap() on none")


def __result_panic_unwrap() -> object:
    s_trap("called result.unwrap() on err")


def __result_panic_unwrap_err() -> object:
    s_trap("called result.unwrap_err() on ok")
