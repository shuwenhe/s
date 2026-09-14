# Thin Bootstrap Bridge Design

## Problem

The user-facing modular compiler path is intended to use the canonical compiler pipeline:

```text
canonical parser -> semantic -> monomorphization -> ownership/lowering -> backend_elf64
```

The current bootstrap artifact `.bootstrap/modular/s_modular` is missing. A direct bootstrap attempt with `bin/s_seed` fails while compiling `src/cmd/compile/modular_build_main.s`:

```text
PARSE_FAIL at 4:5 near 'compile.internal.semantic' (tok=STRING)
error[4] at 4:5: expected ), got STRING
```

The compatibility audit shows this is not a small parser-only gap. The canonical modular compiler closure contains 55 files and requires modern S features that `s_seed` does not support as a complete compiler dialect, including multi-entry grouped imports, generic functions, receiver methods, and ownership syntax. The stage discovery audit did not find an existing executable intermediate compiler that can consume the 55-file canonical closure.

## Non-Goals

- Do not expand `s_seed` into a modern S compiler.
- Do not duplicate the canonical parser.
- Do not duplicate semantic analysis.
- Do not duplicate monomorphization.
- Do not duplicate the ownership solver.
- Do not duplicate `backend_elf64`.
- Do not downgrade canonical source from modern `import` syntax to legacy `use` syntax.
- Do not make `bin/s_seed` the user-facing semantic or build authority again.
- Do not touch, revert, or include pre-existing dirty changes such as `src/cmd/compile/internal/backend_elf64.s:3203`.

## Authority Boundary

`s_seed` is allowed to be a bootstrap producer only:

```text
s_seed -> bridge/stage artifact
```

It is not allowed to decide user program semantics in the modular native path:

```text
user source -> s_seed -> legacy semantics
```

The first artifact that is allowed to own modern language semantics is the canonical modular compiler produced through the bridge:

```text
.bootstrap/modular/s_modular
  -> canonical parser
  -> semantic
  -> mono
  -> ownership/lowering
  -> backend_elf64
```

## Bootstrap Stages

The target chain is:

```text
s_seed
  -> thin bootstrap bridge
  -> .bootstrap/modular/s_modular.stage1
  -> .bootstrap/modular/s_modular.stage2
  -> .bootstrap/modular/s_modular
```

Stage meanings:

- `s_seed`: trusted C seed compiler; only produces the bridge or another bootstrap-only artifact.
- Thin bridge: seed-compatible bootstrap mechanism that crosses into canonical compiler sources.
- `s_modular.stage1`: first canonical modular compiler artifact produced by the bridge.
- `s_modular.stage2`: canonical modular compiler rebuilt by stage1.
- `s_modular`: installed canonical modular compiler chosen after stage checks pass.

## Bridge Responsibilities

The bridge may:

- Compute or consume the dependency closure for `src/cmd/compile/modular_build_main.s`.
- Assemble module inputs into a bootstrap form that existing bootstrap/native primitives can consume.
- Normalize bootstrap-only source packaging where the normalization does not change canonical language semantics.
- Invoke existing bootstrap/native primitives.
- Orchestrate stage artifact paths, logs, reports, and checks.
- Produce clear failure reports for parse, semantic, mono, backend, and execution boundaries.

## Forbidden Responsibilities

The bridge must not:

- Implement a second parser for canonical S.
- Implement a second type checker or semantic resolver.
- Implement a second monomorphizer.
- Implement ownership or NLL analysis.
- Implement a second native backend.
- Rewrite canonical source files from modern dialect into seed dialect.
- Treat successful legacy compilation as proof of canonical semantic correctness.

## Artifact Layout

Bootstrap artifacts live under `.bootstrap/modular`:

```text
.bootstrap/modular/
  bootstrap-compat-audit.txt
  bootstrap-stage-discovery.txt
  bridge-report.txt
  s_modular.stage1
  s_modular.stage2
  s_modular
```

`bin/s_modular` remains a user-facing wrapper. It may delegate to `.bootstrap/modular/s_modular` when that canonical artifact exists. It must not fall back to `s_seed` for `check`, `tokens`, `ast`, `build`, or `test`.

## Dependency Closure Handling

The canonical entry is:

```text
src/cmd/compile/modular_build_main.s
```

The bridge must treat canonical imports as source truth. Closure discovery must understand:

- grouped `import (...)`
- single-line `import "..."`
- legacy `use ...` where it still exists
- package index mappings from `scripts/s-package-index.tsv`

Closure handling is a bootstrap packaging concern only. It must not require changing canonical source to fit seed syntax.

## Stage Transition

Each transition must be explicit and reported:

```text
B0 bridge exists
B1 seed can produce bridge
B2 bridge can consume canonical dependency closure
B3 canonical parser runs
B4 canonical semantic runs
B5 canonical mono runs
B6 canonical backend builds compiler
B7 .bootstrap/modular/s_modular exists
B8 stage1 rebuilds stage2
B9 generic-method-native-e2e returns 42
```

Early implementations may stop at the first failing boundary, but the failure must be assigned to one of these stages.

## Failure Model

Reports must distinguish:

- artifact missing
- artifact not executable
- parse failure
- semantic failure
- mono failure
- generic residue failure
- backend failure
- execution failure
- reproducibility failure

Failures should include the candidate/stage name, producer, source entry, first failing file where known, first failing line where known, and a concise reason.

## Reproducibility

The first reproducibility target is semantic and functional, not byte-for-byte ELF identity:

```text
s_seed -> bridge -> s_modular.stage1
s_modular.stage1 -> s_modular.stage2
s_modular.stage2 runs canonical gates
```

Byte-for-byte identity may be added later if ELF metadata, timestamps, and build IDs are controlled.

The stage1 and stage2 compilers must both keep `s_seed` out of user-facing build authority.

## Exit Criteria

The bridge design is complete when the following gates can pass in order:

```text
make modular-bootstrap-stage-discovery
make modular-bootstrap
make modular-bootstrap-check
make modular-native-driver-check
make modular-generic-parse-check
make modular-generic-mono-pipeline-check
make generic-method-native-e2e-check
```

The final acceptance condition is:

```text
real S source with Box[int].get()
  -> canonical parse
  -> semantic method resolution
  -> generic receiver method monomorphization
  -> zero generic residue
  -> backend_elf64
  -> native executable
  -> exit status 42
```

## Current Evidence

`make modular-bootstrap-compat-audit` reports:

```text
closure-files=55
multi-entry grouped import=23 FAIL
generic function=12 FAIL
receiver method=84 FAIL
ownership syntax=728 FAIL
Decision=staged-bootstrap-bridge
```

`make modular-bootstrap-stage-discovery` reports:

```text
Decision=B-thin-bootstrap-bridge
Shortest-chain=UNAVAILABLE
status=blocked-no-reusable-existing-stage
```

This closes the route of extending `s_seed` for modern canonical compiler support and selects a thin bridge as the next architecture.
