# Runtime Bridge

This directory hosts the temporary execution bridge for self-hosting work.

Current purpose:

- define concrete host-side behavior for self-hosted runtime intrinsics
- provide a validation layer before the S frontend is directly executable
- keep runtime-oriented tooling separate from `std/`, which remains the S-side API surface

Files:

- `python_bridge.py`: host implementation of the current intrinsic contract
- `validate_outputs.py`: golden-output validator for lexer/parser-facing behavior

This bridge is intentionally transitional. The long-term goal is to replace it with a real S runtime or a lower-level execution backend.
