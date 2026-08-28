# Bootstrap Ladder

This repository follows the same basic bootstrapping shape as the Go toolchain:

1. A trusted seed compiler builds the first executable artifact.
2. That artifact rebuilds the compiler sources.
3. The rebuilt compiler rebuilds the same sources again.
4. The second and third outputs are compared for convergence.

The Go toolchain does this in `cmd/dist bootstrap` by building toolchain1,
then `go_bootstrap`, then toolchain2 and toolchain3. The S repository mirrors
that pattern with a smaller ladder focused on the compiler frontend and native
runtime.

## Current stages

- `make bootstrap-stage0`
  - Builds the trusted C seed compiler as `bin/s_seed`.
- `make bootstrap-convergence`
  - Uses `bin/s_seed` to build `src/cmd/compile/main.s` into staged IR and
    verifies that the stage2 and stage3 IR match.
- `make bootstrap-pure-s`
  - Runs the pure-S bootstrap entrypoint in
    `src/cmd/compile/selfhost/bootstrap_pure_s.s`.
- `make native-bootstrap`
  - Runs the pure-S bootstrap ladder and compares the stage2 and stage3
    binaries.
- `make true-selfhost-check`
  - Verifies the installed compiler no longer carries the C seed or libc
    symbols.

## Notes

- `src/cmd/compile/selfhost/compiler.s` is the current self-hosted compiler
  core.
- `src/cmd/compile/selfhost/bootstrap_pure_s.s` is the pure-S bootstrap driver.
- `src/cmd/dist/native-bootstrap.sh` is the shell entrypoint that wires the
  seed compiler to the pure-S bootstrap binary.

The bootstrap frontier is intentionally incremental. Each slice is expected to
close a small semantic gap before the next slice is attempted.

