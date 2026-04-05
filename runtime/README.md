# Runtime Bridge

This directory hosts the temporary execution bridge for self-hosting work.

Current purpose:

- define concrete host-side behavior for self-hosted runtime intrinsics
- provide a validation layer before the S frontend is directly executable
- keep runtime-oriented tooling separate from `std/`, which remains the S-side API surface

Files:

- `python_bridge.py`: host implementation of the current intrinsic contract
- `s_native_runner.c`: minimal non-Python runner for the current `hello.s` / `sum.s` build subset
- `s_native_runner.s`: S-native source version of the same native-runner MVP
- `intrinsic_dispatch.py`: dispatcher from S-side intrinsic symbols to bridge calls
- `hosted_frontend.py`: hosted lexer/parser pipeline that emits and executes `IntrinsicCall`
- `check_bridge.py`: minimal bridge self-check for intrinsic execution
- `validate_outputs.py`: golden-output validator for lexer/parser-facing behavior

For the current MVP there are now two runtime tracks:

- Python-hosted execution for the broader self-hosting workflow
- a native C runner that can build the current `hello.s` / `sum.s` subset without Python

This bridge is intentionally transitional. The long-term goal is to replace it with a real S runtime or a lower-level execution backend.

Transition design:

- [runtime_transition.md](/app/s/docs/runtime_transition.md): phased plan for shrinking and replacing the Python host bridge
