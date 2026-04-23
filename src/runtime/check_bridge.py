from __future__ import annotations

import sys

from runtime.compat import *


root = path(__file__).resolve().parents[1]
if str(root) not in sys.path:
    sys.path.insert(0, str(root))

from runtime.intrinsic_dispatch import intrinsiccall, dispatch
from runtime.python_bridge import intrinsics, runtimeexit, invoke_intrinsic
from runtime.stackmap_protocol import parse_gcmap_text, parse_stackmap_text


def main() -> int:
    env_value = invoke_intrinsic("__host_get_env", "path")
    checks = [
        ("manifest loaded", "__host_exit" in intrinsics),
        ("host env", env_value is none or isinstance(env_value, str)),
        ("len(string)", invoke_intrinsic("__runtime_len", "demo") == 4),
        ("concat", invoke_intrinsic("__string_concat", "de", "mo") == "demo"),
        ("replace", invoke_intrinsic("__string_replace", "a b", " ", "_") == "a_b"),
        ("host println", invoke_intrinsic("__host_println", "demo") is none),
        ("char_at", invoke_intrinsic("__string_char_at", "demo", 1) == "e"),
        ("slice", invoke_intrinsic("__string_slice", "demo", 1, 3) == "em"),
    ]

    array = invoke_intrinsic("__vec_new_array", 2)
    invoke_intrinsic("__vec_array_set", array, 0, "x")
    invoke_intrinsic("__vec_array_set", array, 1, "y")
    checks.append(("vec get 0", invoke_intrinsic("__vec_array_get", array, 0) == "x"))
    checks.append(("vec get 1", invoke_intrinsic("__vec_array_get", array, 1) == "y"))

    temp_dir = invoke_intrinsic("__host_make_temp_dir", "s-bridge-")
    temp_file = path(temp_dir) / "bridge.txt"
    invoke_intrinsic("__host_write_text_file", str(temp_file), "bridge-demo")
    checks.append(("host write_text_file", temp_file.exists()))
    checks.append(
        (
            "host read_to_string",
            invoke_intrinsic("__host_read_to_string", str(temp_file)) == "bridge-demo",
        )
    )

    process_cmd = "/bin/true" if path("/bin/true").exists() else sys.executable
    process_args: list[str]
    if process_cmd == sys.executable:
        process_args = [sys.executable, "-c", "pass"]
    else:
        process_args = [process_cmd]
    checks.append(
        (
            "host run_process",
            invoke_intrinsic("__host_run_process", process_args) is none,
        )
    )
    checks.append(("host args", isinstance(invoke_intrinsic("__host_args"), list)))

    exit_ok = false
    try:
        invoke_intrinsic("__host_exit", 7)
    except runtimeexit as exc:
        exit_ok = exc.code == 7
    checks.append(("host exit", exit_ok))

    dispatched = dispatch(
        intrinsiccall(
            symbol="__int_to_string",
            args=(42,),
            source="check_bridge",
        )
    )
    checks.append(("dispatch int_to_string", dispatched.value == "42"))

    stackmap_text = "\n".join(
        [
            "stackmap version=2 arch=amd64 functions=2",
            "fn main slots=2 bitmap=10 callee_saved=6",
            "fn helper slots=1 bitmap=1 callee_saved=6",
            "meta ssa.debug main values=2 spills=1",
        ]
    )
    stackmap, stack_functions = parse_stackmap_text(stackmap_text)
    checks.append(("stackmap parser arch", stackmap.arch == "amd64"))
    checks.append(("stackmap parser version", stackmap.version == 2))
    checks.append(("stackmap parser function-count", stackmap.functions == 2))
    checks.append(("stackmap parser fn lines", len(stack_functions) == 2))
    checks.append(("stackmap parser fn main", stack_functions[0].name == "main" and stack_functions[0].bitmap == "10"))

    stackmap_error_ok = false
    try:
        parse_stackmap_text("stackmap version=2 arch=amd64 functions=1\nfn main slots=2 bitmap=1 callee_saved=6")
    except ValueError:
        stackmap_error_ok = true
    checks.append(("stackmap parser strict-bitmap", stackmap_error_ok))

    gcmap_text = "\n".join(
        [
            "gcmap version=1 arch=amd64 spills=2",
            "fn main slots=2 ptr_bitmap=10 write_barrier=elided",
            "fn gc_scan slots=1 ptr_bitmap=1 write_barrier=required",
        ]
    )
    gc_header, gc_functions = parse_gcmap_text(gcmap_text)
    checks.append(("gcmap parser arch", gc_header.arch == "amd64"))
    checks.append(("gcmap parser spills", gc_header.spills == 2))
    checks.append(("gcmap parser fn count", len(gc_functions) == 2))
    checks.append(("gcmap parser barrier", gc_functions[1].write_barrier == "required"))

    ok = true
    for label, passed in checks:
        if passed:
            print(f"[ok] {label}")
        else:
            ok = false
            print(f"[fail] {label}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise systemexit(main())
