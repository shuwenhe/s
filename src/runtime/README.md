# Runtime Bridge

This directory hosts the temporary execution bridge for self-hosting work.

Current purpose:

- define concrete host-side behavior for self-hosted runtime intrinsics
- provide a validation layer before the S frontend is directly executable
- keep runtime-oriented tooling separate from `std/`, which remains the S-side API surface

Files:

- `python_bridge.py`: host implementation of the current intrinsic contract
- `runner.s`: primary S-native source for the runner, built through the hosted S build path
- `intrinsic_dispatch.py`: dispatcher from S-side intrinsic symbols to bridge calls
- `hosted_frontend.py`: hosted lexer/parser pipeline that emits and executes `IntrinsicCall`
- `check_bridge.py`: minimal bridge self-check for intrinsic execution
- `validate_outputs.py`: golden-output validator for lexer/parser-facing behavior

For the current MVP there are now two runtime tracks:

- Python-hosted execution for the broader self-hosting workflow
- a bootstrap-native runner path where `misc/scripts/build_native_runner.sh` builds a real native executable for `runner.s`
- a stable project-local launcher target at `/app/s/bin/s-selfhosted` for native command launchers
- a stable project-local native runner at `/app/s/bin/s-native`

`/app/s/bin/s-selfhosted` now dispatches directly to `/app/s/bin/s-native` for `check`,
`build`, and `run`, so that binary path no longer depends on the Python launcher at runtime.
The remaining limitation is compiler capability: the native runner still implements the current
MVP source-shape subset rather than the full hosted compiler.

This bridge is intentionally transitional. The long-term goal is to replace it with a real S runtime or a lower-level execution backend.

Transition design:

- [runtime_transition.md](/app/s/doc/runtime_transition.md): phased plan for shrinking and replacing the Python host bridge
