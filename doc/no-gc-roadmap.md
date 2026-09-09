# No-GC Compiler Roadmap

The default `s` driver should be a no-GC ownership compiler for supported
programs. The compatibility seed path remains available through `s --seed`.

## Current Contract

- `s input.s` emits a native executable beside the source.
- `s input.s -o output`, `s -o output input.s`, and `s build input.s -o output`
  emit an explicitly named native executable.
- Supported programs lower through `bin/s_compiler --emit-c` and link only
  `src/runtime/compiler_runtime.h`.
- Generated binaries must not contain S GC, seed interpreter, or
  `runtime_execute` symbols.

## Near-Term Language Work

1. Add minimal structs with deterministic field cleanup.
2. Improve diagnostics for unsupported syntax so users see the no-GC subset
   boundary clearly.

## Completed Language Work

- Semicolons are optional for supported no-GC statements.
- `for (init; condition; step) { ... }` lowers through the existing `while`
  representation for integer loop variables.
- Plain `void` helper calls are supported as statements.
- Local string literal bindings are supported as borrowed `const char *` values
  with no heap ownership or GC participation.

## Verification Gates

- `make compiler-check` must compile and run ownership examples, reject borrow
  violations, compile hello, and check symbols for GC/runtime leaks.
- `sh test/cli/check.sh` must cover default output, `-o`, legacy `build`, help,
  invalid sources, and input/output overwrite protection.
- `make benchmark` must build the no-GC S benchmark and available comparison
  compilers without making unsupported speed claims.

## Non-Goals For This Stage

- Full Rust compatibility.
- Full Go-compatible package and standard library support.
- Claiming S is faster than Rust or C before repeated benchmark evidence.
- Linking the general S runtime GC into default generated applications.
