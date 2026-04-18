# internal toolchain packages

this directory is reserved for implementation details that should stay private
to the s toolchain.

planned responsibilities:

- `bootstrap/`: python-hosted and migration-only bootstrap layers
- `buildcfg/`: build-mode and target configuration
- `toolchain/`: assembler, linker, and host tool invocation helpers
- `platform/`: os and architecture specific support code
- `testenv/`: test-only environment setup and host capability checks

current code is still centered in `src/compiler` and `src/runtime`. new
non-public helpers should land here first instead of growing those packages.

implemented building blocks currently include the `buildcfg/` skeleton.
the current `buildcfg/` skeleton exposes `target`, `toolchain`, and `buildcfg`
records for the compiler entry path.
the current arch dispatch layer lives under `cmd/compile/internal/arch/`.
