from __future__ import annotations

import runtime.intrinsics_impl as impl


intrinsics = {
    "__runtime_len": (impl.__runtime_len, 1),
    "__int_to_string": (impl.__int_to_string, 1),
    "__string_concat": (impl.__string_concat, 2),
    "__string_replace": (impl.__string_replace, 3),
    "__string_char_at": (impl.__string_char_at, 2),
    "__string_slice": (impl.__string_slice, 3),
    "__vec_new_array": (impl.__vec_new_array, 1),
    "__vec_array_get": (impl.__vec_array_get, 2),
    "__vec_array_set": (impl.__vec_array_set, 3),
    "__host_read_to_string": (impl.__host_read_to_string, 1),
    "__host_write_text_file": (impl.__host_write_text_file, 2),
    "__host_make_temp_dir": (impl.__host_make_temp_dir, 1),
    "__host_build_executable": (impl.__host_build_executable, 2),
    "__host_run_process": (impl.__host_run_process, 1),
    "__host_run_process1": (impl.__host_run_process1, 1),
    "__host_run_process5": (impl.__host_run_process5, 5),
    "__host_run_process_argv": (impl.__host_run_process_argv, 1),
    "__host_run_shell": (impl.__host_run_shell, 1),
    "__host_args": (impl.__host_args, 0),
    "__host_get_env": (impl.__host_get_env, 1),
    "__host_exit": (impl.__host_exit, 1),
    "__host_println": (impl.__host_println, 1),
    "__host_eprintln": (impl.__host_eprintln, 1),
    "__option_panic_unwrap": (impl.__option_panic_unwrap, 0),
    "__result_panic_unwrap": (impl.__result_panic_unwrap, 0),
    "__result_panic_unwrap_err": (impl.__result_panic_unwrap_err, 0),
}


def get_intrinsic(name: str):
    if name not in intrinsics:
        raise Exception(f"S_TRAP: unknown intrinsic {name}")
    return intrinsics[name]


def invoke_intrinsic(name: str, *args: any) -> any:
    func, arity = get_intrinsic(name)
    if len(args) != arity:
        raise Exception(f"S_TRAP: intrinsic {name} expected {arity} args, got {len(args)}")
    return func(*args)


def list_intrinsics():
    return sorted(intrinsics)


def list_specs():
    return [intrinsics[name] for name in list_intrinsics()]
