from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable

import runtime.intrinsics_impl as impl
from runtime.intrinsics_impl import HostArray, IntrinsicSpec, RuntimeExit, RuntimeTrap


_LOCAL_INTRINSICS: dict[str, IntrinsicSpec] = {
    "__runtime_len": IntrinsicSpec("__runtime_len", impl.__runtime_len, 1, "int32"),
    "__int_to_string": IntrinsicSpec("__int_to_string", impl.__int_to_string, 1, "string"),
    "__string_concat": IntrinsicSpec("__string_concat", impl.__string_concat, 2, "string"),
    "__string_replace": IntrinsicSpec("__string_replace", impl.__string_replace, 3, "string"),
    "__string_char_at": IntrinsicSpec("__string_char_at", impl.__string_char_at, 2, "string"),
    "__string_slice": IntrinsicSpec("__string_slice", impl.__string_slice, 3, "string"),
    "__vec_new_array": IntrinsicSpec("__vec_new_array", impl.__vec_new_array, 1, "Array[T]"),
    "__vec_array_get": IntrinsicSpec("__vec_array_get", impl.__vec_array_get, 2, "T"),
    "__vec_array_set": IntrinsicSpec("__vec_array_set", impl.__vec_array_set, 3, "()"),
    "__host_read_to_string": IntrinsicSpec(
        "__host_read_to_string",
        impl.__host_read_to_string,
        1,
        "string",
        "bridge success path returns payload; host failures raise RuntimeTrap",
    ),
    "__host_write_text_file": IntrinsicSpec(
        "__host_write_text_file",
        impl.__host_write_text_file,
        2,
        "()",
        "bridge success path returns unit; host failures raise RuntimeTrap",
    ),
    "__host_make_temp_dir": IntrinsicSpec(
        "__host_make_temp_dir",
        impl.__host_make_temp_dir,
        1,
        "string",
        "bridge success path returns payload; host failures raise RuntimeTrap",
    ),
    "__host_build_executable": IntrinsicSpec(
        "__host_build_executable",
        impl.__host_build_executable,
        2,
        "int32",
        "bridge success path returns exit code; host failures raise RuntimeTrap",
    ),
    "__host_run_process": IntrinsicSpec(
        "__host_run_process",
        impl.__host_run_process,
        1,
        "()",
        "bridge success path returns unit; host failures raise RuntimeTrap",
    ),
    "__host_run_process1": IntrinsicSpec(
        "__host_run_process1",
        impl.__host_run_process1,
        1,
        "int32",
        "bridge success path returns exit code; host failures raise RuntimeTrap",
    ),
    "__host_run_process5": IntrinsicSpec(
        "__host_run_process5",
        impl.__host_run_process5,
        5,
        "int32",
        "bridge success path returns exit code; host failures raise RuntimeTrap",
    ),
    "__host_run_process_argv": IntrinsicSpec(
        "__host_run_process_argv",
        impl.__host_run_process_argv,
        1,
        "int32",
        "bridge success path returns exit code; host failures raise RuntimeTrap",
    ),
    "__host_run_shell": IntrinsicSpec(
        "__host_run_shell",
        impl.__host_run_shell,
        1,
        "int32",
        "bridge success path returns exit code; host failures raise RuntimeTrap",
    ),
    "__host_args": IntrinsicSpec(
        "__host_args",
        impl.__host_args,
        0,
        "Vec[string]",
        "bridge success path returns argv without the executable name",
    ),
    "__host_get_env": IntrinsicSpec(
        "__host_get_env",
        impl.__host_get_env,
        1,
        "Option[string]",
        "bridge success path returns environment values when present",
    ),
    "__host_exit": IntrinsicSpec(
        "__host_exit",
        impl.__host_exit,
        1,
        "never",
        "host process termination boundary for S command wrappers",
    ),
    "__host_println": IntrinsicSpec("__host_println", impl.__host_println, 1, "()"),
    "__host_eprintln": IntrinsicSpec("__host_eprintln", impl.__host_eprintln, 1, "()"),
    "__option_panic_unwrap": IntrinsicSpec("__option_panic_unwrap", impl.__option_panic_unwrap, 0, "never"),
    "__result_panic_unwrap": IntrinsicSpec("__result_panic_unwrap", impl.__result_panic_unwrap, 0, "never"),
    "__result_panic_unwrap_err": IntrinsicSpec("__result_panic_unwrap_err", impl.__result_panic_unwrap_err, 0, "never"),
}


def _load_manifest()  dict[str, IntrinsicSpec]:
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


def _validate_manifest(manifest_specs: dict[str, IntrinsicSpec])  None:
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


def get_intrinsic(name: str)  IntrinsicSpec:
    try:
        return INTRINSICS[name]
    except KeyError as exc:
        raise RuntimeTrap(f"unknown intrinsic {name}") from exc


def invoke_intrinsic(name: str, *args: Any)  Any:
    spec = get_intrinsic(name)
    if len(args) != spec.arity:
        raise RuntimeTrap(
            f"intrinsic {name} expected {spec.arity} args, got {len(args)}"
        )
    return spec.func(*args)


def list_intrinsics()  Iterable[str]:
    return sorted(INTRINSICS)


def list_specs()  list[IntrinsicSpec]:
    return [INTRINSICS[name] for name in list_intrinsics()]
