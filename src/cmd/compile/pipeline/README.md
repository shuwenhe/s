# Compile pipeline map

This directory describes the canonical S compiler pipeline. It is a source
navigation layer first: it records the intended stage order, artifact flow, and
boundary rules without changing the current compiler execution path.

Current implementation note:

- `../compiler.s` still owns the seed-hosted no-GC compiler path and the current
  proof emitters.
- `../internal/*` still contains the existing frontend, middle-end, backend, and
  target support code.
- New stage directories at `../syntax`, `../resolve`, `../semantic`, `../mir`,
  `../ownership`, `../mono`, `../layout`, `../backend/abi`, `../codegen`, and
  `../object` are the canonical homes for future migrated implementation.

Directory migration must not advance the proven frontier. A frontier advances
only when a real compiler capability is implemented and proven by the pipeline
gates.

