# runtime bridge

this directory hosts the temporary execution bridge for self-hosting work.

current purpose:

- define concrete host-side behavior for self-hosted runtime intrinsics
- provide a validation layer before the s frontend is directly executable
- keep runtime-oriented tooling separate from `std/`, which remains the s-side api surface

files:

- `python_bridge.py`: host implementation of the current intrinsic contract
- `runner.s`: primary s_arm64 source for the runner, built through the hosted s build path
- `intrinsic_dispatch.py`: dispatcher from s-side intrinsic symbols to bridge calls
- `hosted_frontend.py`: hosted lexer/parser pipeline that emits and executes `intrinsiccall`
- `check_bridge.py`: minimal bridge self-check for intrinsic execution
- `validate_outputs.py`: golden-output validator for lexer/parser-facing behavior

for the current mvp there are now two runtime tracks:

- python-hosted execution for the broader self-hosting workflow
- an s-side runner entrypoint in `runner.s` that now goes through the hosted compiler bridge
- a project-local command launcher target at `/app/s/bin/s-selfhosted`
- a project-local compiler launcher target at `/app/s/bin/s_arm64`

`build` and `run` now execute through host intrinsics instead of a separate native runner hop.
that removes the extra runner dependency from the active path, while the remaining bridge code
stays available as transitional infrastructure.

the bootstrap sequence that produces `s_compiler_stage1`, `s_final_compiler`,
and `bin/s_arm64` is documented in
[`doc/bootstrap_flow.md`](/app/s/doc/bootstrap_flow.md). that document is the
canonical reference for the current stage1/full-build ordering.
[`misc/scripts/verify_bootstrap_flow.sh`](/app/s/misc/scripts/verify_bootstrap_flow.sh)
is the smoke test for that flow.

this bridge is intentionally transitional. the long-term goal is to replace it with a real s runtime or a lower-level execution backend.

transition design:

- [runtime_transition.md](/app/s/doc/runtime_transition.md): phased plan for shrinking and replacing the python host bridge
