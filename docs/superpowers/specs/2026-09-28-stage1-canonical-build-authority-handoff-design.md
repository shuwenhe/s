# Stage1 Canonical Build Authority Handoff Design

Date: 2026-09-28

## Purpose

Make the current bootstrap P0 explicit: Stage1 must stop using the bootstrap
subset as the `build` authority and must hand `build` execution to the
canonical modular compiler path.

The target proof chain is:

```text
Stage1 build command
  -> generated canonical entry
  -> modular_build_main.main
  -> compile.internal.backend_elf64.build
  -> canonical semantic/compiler pipeline
  -> native Stage2 artifact
```

Until this chain is proven by real Stage1 execution,
`stage1-canonical-entry-linkage=PROVEN` is the only P0.

## Current State

`make modular-bootstrap` builds `.bootstrap/modular/s_modular-stage1` through
the explicit C Stage0. Stage1 carries the canonical source closure, and the
closure includes `src/cmd/compile/modular_build_main.s` plus the canonical
backend files.

The authority handoff is not complete. Stage1's generated `build` command
still dispatches to `bootstrap_subset_build(argv[2], argv[4])`. The canonical
closure is materialized as payload/metadata, but it is not the executable
compiler authority for `build`.

The expected failing evidence today is:

```text
stage1-generated-build-handler=bootstrap_subset_build
stage1-canonical-entry-linkage=NOT_PROVEN
bootstrap-subset-build-authority=UNCHANGED
production-compiler-bootstrap=NOT_PROVEN
```

## Non-Goals

This phase must not:

- Expand the seed parser, seed semantic analyzer, or seed name resolver.
- Add more language coverage to `bootstrap_subset_build`.
- Rename `bootstrap_subset_build` to a canonical-sounding function while still
  executing the same subset path.
- Work on Stage2/Stage3 convergence before Stage1 canonical entry linkage is
  proven.
- Refactor the canonical backend except where a minimal, direct proof hook is
  required to expose real execution.

## Design

Stage0 remains the one-time lifter that creates Stage1. Its job in this phase
is to generate a Stage1 whose `build` command enters a generated canonical
entry instead of `bootstrap_subset_build`.

The generated canonical entry must be tied to the canonical closure contents,
not to an independent handwritten subset implementation. For this milestone,
the important property is not that Stage0 becomes a full S compiler. The
important property is that the Stage1 runtime path for `build` is the canonical
modular compiler entry and backend authority.

The Stage1 `build` branch should therefore have this shape:

```text
if command == build:
  validate CLI shape
  call generated canonical build entry
```

The generated canonical build entry must expose runtime evidence that it
entered:

```text
modular_build_main.main
compile.internal.backend_elf64.build
canonical parser/semantic or later canonical compiler pipeline
```

That evidence must come from executing Stage1 against a real input and
producing a native output artifact. Source grep, closure metadata, embedded
strings, or marker-only checks are insufficient.

## Verification Gates

The first implementation phase is complete only when all of these pass because
of real Stage1 execution:

```sh
make stage1-build-authority-check
make stage1-canonical-entry-linkage-check
bash misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh
```

The checks should reject these false positives:

- `stage1-generated-build-handler=canonical_build` where the runtime output
  still contains `bootstrap-subset:` diagnostics.
- A Stage1 binary that only proves the canonical closure was embedded.
- A Stage1 binary that can build a fixture through a hardcoded or template
  path without entering `modular_build_main.main`.
- A report that is satisfied by static source inspection alone.

## Acceptance Criteria

The milestone is accepted when the reports prove:

```text
stage1-build-authority=PASS
stage1-canonical-entry-linkage=PROVEN
stage1-generated-build-handler=canonical_build
bootstrap-subset-runtime-path=NO
canonical-backend-build-reached=YES
canonical-semantic-authority=YES
native-stage2-artifact=YES
```

Only after this milestone is accepted should development proceed to:

```text
Stage1 canonical build -> Stage2
Stage2 canonical build -> Stage3
Stage2/Stage3 convergence
production-selfhost-check
true-selfhost-check
```
