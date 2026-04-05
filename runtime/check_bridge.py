from __future__ import annotations

from runtime.intrinsic_dispatch import IntrinsicCall, dispatch
from runtime.python_bridge import HostArray, RuntimeTrap, invoke_intrinsic


def main() -> int:
    checks = [
        ("len(string)", invoke_intrinsic("__runtime_len", "demo") == 4),
        ("char_at", invoke_intrinsic("__string_char_at", "demo", 1) == "e"),
        ("slice", invoke_intrinsic("__string_slice", "demo", 1, 3) == "em"),
    ]

    array = invoke_intrinsic("__vec_new_array", 2)
    invoke_intrinsic("__vec_array_set", array, 0, "x")
    invoke_intrinsic("__vec_array_set", array, 1, "y")
    checks.append(("vec get 0", invoke_intrinsic("__vec_array_get", array, 0) == "x"))
    checks.append(("vec get 1", invoke_intrinsic("__vec_array_get", array, 1) == "y"))

    dispatched = dispatch(
        IntrinsicCall(
            symbol="__int_to_string",
            args=(42,),
            source="check_bridge",
        )
    )
    checks.append(("dispatch int_to_string", dispatched.value == "42"))

    ok = True
    for label, passed in checks:
        if passed:
            print(f"[ok] {label}")
        else:
            ok = False
            print(f"[fail] {label}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
