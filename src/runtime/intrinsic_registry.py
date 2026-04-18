from __future__ import annotations

import json
from pathlib import path
from typing import any, iterable

import runtime.intrinsics_impl as impl
from runtime.intrinsics_impl import hostarray, intrinsicspec, runtimeexit, runtimetrap


_local_intrinsics: dict[str, intrinsicspec] = {
    "__runtime_len": intrinsicspec("__runtime_len", impl.__runtime_len, 1, "int32"),
    "__int_to_string": intrinsicspec("__int_to_string", impl.__int_to_string, 1, "string"),
    "__string_concat": intrinsicspec("__string_concat", impl.__string_concat, 2, "string"),
    "__string_replace": intrinsicspec("__string_replace", impl.__string_replace, 3, "string"),
    "__string_char_at": intrinsicspec("__string_char_at", impl.__string_char_at, 2, "string"),
    "__string_slice": intrinsicspec("__string_slice", impl.__string_slice, 3, "string"),
    "__vec_new_array": intrinsicspec("__vec_new_array", impl.__vec_new_array, 1, "array[t]"),
    "__vec_array_get": intrinsicspec("__vec_array_get", impl.__vec_array_get, 2, "t"),
    "__vec_array_set": intrinsicspec("__vec_array_set", impl.__vec_array_set, 3, "()"),
    "__host_read_to_string": intrinsicspec(
        "__host_read_to_string",
        impl.__host_read_to_string,
        1,
        "string",
        "bridge success path returns payload; host failures raise runtimetrap",
    ),
    "__host_write_text_file": intrinsicspec(
        "__host_write_text_file",
        impl.__host_write_text_file,
        2,
        "()",
        "bridge success path returns unit; host failures raise runtimetrap",
    ),
    "__host_make_temp_dir": intrinsicspec(
        "__host_make_temp_dir",
        impl.__host_make_temp_dir,
        1,
        "string",
        "bridge success path returns payload; host failures raise runtimetrap",
    ),
    "__host_build_executable": intrinsicspec(
        "__host_build_executable",
        impl.__host_build_executable,
        2,
        "int32",
        "bridge success path returns exit code; host failures raise runtimetrap",
    ),
    "__host_run_process": intrinsicspec(
        "__host_run_process",
        impl.__host_run_process,
        1,
        "()",
        "bridge success path returns unit; host failures raise runtimetrap",
    ),
    "__host_run_process1": intrinsicspec(
        "__host_run_process1",
        impl.__host_run_process1,
        1,
        "int32",
        "bridge success path returns exit code; host failures raise runtimetrap",
    ),
    "__host_run_process5": intrinsicspec(
        "__host_run_process5",
        impl.__host_run_process5,
        5,
        "int32",
        "bridge success path returns exit code; host failures raise runtimetrap",
    ),
    "__host_run_process_argv": intrinsicspec(
        "__host_run_process_argv",
        impl.__host_run_process_argv,
        1,
        "int32",
        "bridge success path returns exit code; host failures raise runtimetrap",
    ),
    "__host_run_shell": intrinsicspec(
        "__host_run_shell",
        impl.__host_run_shell,
        1,
        "int32",
        "bridge success path returns exit code; host failures raise runtimetrap",
    ),
    "__host_args": intrinsicspec(
        "__host_args",
        impl.__host_args,
        0,
        "vec[string]",
        "bridge success path returns argv without the executable name",
    ),
    "__host_get_env": intrinsicspec(
        "__host_get_env",
        impl.__host_get_env,
        1,
        "option[string]",
        "bridge success path returns environment values when present",
    ),
    "__host_exit": intrinsicspec(
        "__host_exit",
        impl.__host_exit,
        1,
        "never",
        "host process termination boundary for s command wrappers",
    ),
    "__host_println": intrinsicspec("__host_println", impl.__host_println, 1, "()"),
    "__host_eprintln": intrinsicspec("__host_eprintln", impl.__host_eprintln, 1, "()"),
    "__option_panic_unwrap": intrinsicspec("__option_panic_unwrap", impl.__option_panic_unwrap, 0, "never"),
    "__result_panic_unwrap": intrinsicspec("__result_panic_unwrap", impl.__result_panic_unwrap, 0, "never"),
    "__result_panic_unwrap_err": intrinsicspec("__result_panic_unwrap_err", impl.__result_panic_unwrap_err, 0, "never"),
}


def _load_manifest() -> dict[str, intrinsicspec]:
    manifest_path = path(__file__).with_name("intrinsics_manifest.json")
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest_specs: dict[str, intrinsicspec] = {}
    for item in data["intrinsics"]:
        name = item["name"]
        func = _local_intrinsics.get(name)
        if func is none:
            raise runtimetrap(f"manifest declares intrinsic without bridge implementation: {name}")
        manifest_specs[name] = intrinsicspec(
            name=name,
            func=func.func,
            arity=int(item["arity"]),
            returns=item["returns"],
            notes=item.get("notes", ""),
        )
    return manifest_specs


def _validate_manifest(manifest_specs: dict[str, intrinsicspec]) -> none:
    local_names = set(_local_intrinsics)
    manifest_names = set(manifest_specs)
    missing = sorted(local_names - manifest_names)
    if missing:
        raise runtimetrap(
            "local bridge intrinsics missing from manifest: " + ", ".join(missing)
        )
    for name, spec in manifest_specs.items():
        local = _local_intrinsics[name]
        if local.arity != spec.arity:
            raise runtimetrap(
                f"manifest arity mismatch for {name}: local={local.arity} manifest={spec.arity}"
            )
        if local.returns != spec.returns:
            raise runtimetrap(
                f"manifest return mismatch for {name}: local={local.returns} manifest={spec.returns}"
            )


intrinsics = _load_manifest()
_validate_manifest(intrinsics)


def get_intrinsic(name: str) -> intrinsicspec:
    try:
        return intrinsics[name]
    except keyerror as exc:
        raise runtimetrap(f"unknown intrinsic {name}") from exc


def invoke_intrinsic(name: str, *args: any) -> any:
    spec = get_intrinsic(name)
    if len(args) != spec.arity:
        raise runtimetrap(
            f"intrinsic {name} expected {spec.arity} args, got {len(args)}"
        )
    return spec.func(*args)


def list_intrinsics() -> iterable[str]:
    return sorted(intrinsics)


def list_specs() -> list[intrinsicspec]:
    return [intrinsics[name] for name in list_intrinsics()]
