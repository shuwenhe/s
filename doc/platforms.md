# Host and target support

| Path | Status |
|---|---|
| Linux/amd64 native ELF | Verified self-host baseline; production completeness audit ongoing |
| Linux/amd64 C seed/development build | Used to produce native Stage1 |
| macOS C seed/cross-build experiments | Separate from verified native acceptance |
| ARM, ARM64, RISC-V, Windows, WebAssembly and other backend directories | Presence of source does not establish working canonical native production support |

S_HOST_OS/S_HOST_ARCH identify the compiler host; S_TARGET_OS/S_TARGET_ARCH identify the requested output. The canonical native build explicitly rejects targets other than linux/amd64. `make target-info` reports target selection. A cross-built bootstrap stage can execute only on its matching target or through a suitable S_BOOTSTRAP_RUNNER in the bootstrap path supporting it.

Before claiming a new target, implement ABI and runtime boundaries, object/executable emission and linker integration; run native execution, negative validation, GC/root stress and clean-room staged self-hosting on that target. Preserve reproducibility and publish exact revision/evidence. Architecture files alone are not acceptance.
