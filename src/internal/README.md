# Internal Toolchain Packages

This directory is reserved for implementation details that should stay private
to the S toolchain.

Planned responsibilities:

- `bootstrap/`: Python-hosted and migration-only bootstrap layers
- `buildcfg/`: build-mode, target, and output-path configuration
- `toolchain/`: assembler, linker, and host tool invocation helpers
- `platform/`: OS and architecture specific support code
- `testenv/`: test-only environment setup and host capability checks

Current code is still centered in `src/compiler` and `src/runtime`. New
non-public helpers should land here first instead of growing those packages.

