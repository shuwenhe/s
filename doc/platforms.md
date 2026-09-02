# S host and target platform model

S uses the same separation as Go:

| Name | Meaning |
| --- | --- |
| `S_HOST_OS` / `S_HOST_ARCH` | Platform executing the compiler. |
| `S_TARGET_OS` / `S_TARGET_ARCH` | Platform that will execute the output. |

The target is selected once at the build boundary and is propagated to every
bootstrap stage. A target is not inferred from the host. This makes a cross
build explicit and prevents a macOS assembler from being accidentally used for
a Linux ELF target.

## Current implementation matrix

| Target | Object format | Seed compiler | Independent native backend | Self-host convergence |
| --- | --- | --- | --- | --- |
| `linux/amd64` | ELF | yes | yes | supported bootstrap target |
| `darwin/arm64` | Mach-O | seed runs on host | not yet | not yet |

`make target-info` reports the selected target and whether the native backend
exists. `make target-config-check` verifies target parsing and backend gating.

## Cross bootstrap contract

The Linux/amd64 backend can be built on another host when GNU cross-binutils
are provided. On macOS, `target-env.sh` selects Homebrew's `x86_64-elf-*`
tools if present. Because a Linux ELF compiler cannot run on macOS, the caller
must provide `S_BOOTSTRAP_RUNNER`, a single executable that launches a
Linux/amd64 program. The bootstrap scripts fail before stage execution when
the runner is absent.

## Adding a target

A new target is complete only when all four pieces exist:

1. instruction selection and ABI lowering in `src/cmd/compile`;
2. object writer/linker for its executable format (`ELF`, `Mach-O`, or `PE`);
3. a target runtime implementing process entry, allocation, file I/O, and
   syscalls; and
4. a target-native stage1 → stage2 → stage3 convergence test.

For `darwin/arm64`, this means adding an ARM64 backend, a Mach-O writer, and a
Darwin/ARM64 self-host runtime before advertising native self-host support.
