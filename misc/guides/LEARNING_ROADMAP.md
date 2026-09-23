# S Compiler Bootstrap Roadmap - Current Status Guide

**Date:** 2026-09-23  
**Level:** Quick orientation for the current Bootstrap blocker  
**Status:** supersedes the older `std.io.eprintln` qualified-name blocker summary

---

## 30 Second Summary

S has moved past the early qualified-name blocker. The current Bootstrap problem is no longer "the seed lacks syntax/name-resolution support"; it is whether the Stage1 canonical implementation has truly become the build authority.

Old state:

```text
S source
  ↓
seed parser / semantic
  ↓
import
  ↓
std.io.eprintln
  ✗ qualified resolution blocker
```

Current state:

```text
qualified import/name resolution
  ✓ B6.7.1 import parsing
  ✓ B6.7.2 import registration
  ✓ B6.7.3b declaration identity preservation
  ✓ B6.7.3c qualified name resolution
              ↓
the real problem has moved to
              ↓
whether Stage1 truly executes the canonical compiler
              ↓
whether the canonical runtime target enters Stage1
              ↓
whether Stage1 can build the next compiler generation
```

Do not spend the main effort adding a local `std.io.eprintln` patch or seed-level qualified-call special case in `src/cmd/compile/seed/semantic/analyzer.c`. That was a historical surface blocker, not the current Bootstrap authority blocker.

---

## Current Success Condition

The milestone to pin down is:

```text
M1 = Stage1 canonical compiler
     truly executes the canonical build path
     and successfully produces a runnable Stage2
```

This means "some `.s` file can be compiled by the seed" is not enough. The authority chain must be proven:

```text
Stage0 / seed
    ↓
Stage1
    ↓
canonical modular_build_main
    ↓
backend_elf64.build
    ↓
Stage2
```

Once that chain is proven, Bootstrap changes character: the C seed stops simulating the S compiler and only lifts the real S compiler into existence.

---

## Current RED Evidence

### Qualified Name Resolution Is GREEN/FROZEN

Run:

```bash
bash misc/scripts/check-b6.7.3c-qualified-name-resolution.sh
```

Current key output:

```text
B6.7.3c Qualified Name Resolution=PASS/FROZEN
declaration-identity=PROVEN
resolver-consumes-package-path=PROVEN
qualified-lookup-key=(package_path,name)
std-special-case=NO
qualified-name-resolution=B6.7.3c
classification=B6.7.3c_GREEN
```

This proves the newer resolution path is not a `std.*` special case. It is based on declaration identity and `(package_path, name)` qualified lookup.

### Stage1 Canonical Entry Linkage Is Still RED

Run:

```bash
make stage1-canonical-entry-linkage-check
```

Current key output:

```text
canonical-closure-generated=YES
canonical-closure-has-entry=YES
stage1-generated-c-present=YES
stage1-binary-present=YES
canonical-closure-consumed-by-stage1=METADATA_ONLY
canonical-entry-symbol=NO
canonical-entry-linked=NO
canonical-entry-callable=NO
bootstrap-subset-build-authority=UNCHANGED
missing-capability=stage1-canonical-closure-consumption
stage1-canonical-entry-linkage=NOT_PROVEN
```

Meaning:

```text
the closure exists and includes the canonical entry
the Stage1 artifact exists
but Stage1 only consumes closure metadata
it does not link modular_build_main / backend_elf64 as runtime authority
the build handler is still bootstrap_subset_build
```

This is the current main blocker.

### Stage1 Build Authority Handoff Is Still RED

Run:

```bash
bash misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh
```

Current key output:

```text
stage1-build-entry=YES
stage1-generated-build-handler=bootstrap_subset_build
bootstrap-subset-runtime-path=YES
modular-build-main-reached=NO
canonical-backend-build-reached=NO
canonical-semantic-authority=NO
classification=HANDOFF_RUNTIME_TARGET_GAP
```

Meaning:

```text
Stage1 has a build command entry
but build is not handed to canonical modular_build_main/backend_elf64
it still runs the bootstrap subset runtime target
```

---

## Two Active Mainlines

### 1. Bootstrap Authority

The goal is to prove:

```text
Stage1
  -> canonical modular_build_main.s
  -> compile.internal.backend_elf64.build
  -> canonical parser / semantic / mono / MIR / backend
  -> executable Stage2
```

Primary checks:

```bash
make stage1-canonical-entry-linkage-check
bash misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh
bash misc/scripts/check-b6.7.3e1-canonical-build-runtime-target-audit.sh
```

Key files:

```text
makefile
misc/scripts/stage1-canonical-entry-linkage-check.sh
misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh
misc/scripts/check-b6.7.3e1-canonical-build-runtime-target-audit.sh
src/cmd/compile/modular_build_main.s
src/cmd/compile/internal/backend_elf64.s
```

The current RED does not mean "the seed cannot understand some syntax". It means:

```text
the Stage1 produced by Stage0
does not yet make the canonical build runtime target
callable, linked, executable authority
```

### 2. Canonical Semantic Authority

This line decides whether the self-hosted compiler has one semantic/type/layout authority:

```text
DeclarationRef
    ↓
CanonicalTypeRef
    ↓
Layout Authority
    ↓
ABI classification
    ↓
MIR
    ↓
Codegen
```

Avoid falling back to:

```text
string guessing
seed special cases
backend-only inference
```

Relevant evidence and files:

```text
src/cmd/compile/internal/semantic.s
src/cmd/compile/internal/mono/M1_PROVENANCE_PROOF.md
src/cmd/compile/internal/backend_elf64.s
test/regression/m1_declaration_ref_gate.s
test/regression/m1_identity_threading_gate.s
test/regression/m1_verification_diagnostic.md
```

---

## How To Judge The Next Change

A change is probably not on the mainline if it only makes one probe or one seed-compiled `.s` file pass without proving any of these facts:

```text
Stage1 binary contains canonical entry/backend symbols
Stage1 build command dispatches to canonical build path
Stage1 reaches canonical parser / semantic / backend
Stage1 produces a runnable Stage2
Stage2 can build Stage3
Stage2 and Stage3 converge
```

A change is mainline progress if it turns these REDs GREEN:

```text
stage1-canonical-entry-linkage=PROVEN
classification=B6.7.3e_GREEN
classification=TARGET_EXISTS
Stage1->Stage2=PROVEN
Stage2->Stage3=PROVEN
Stage2/Stage3-equivalence=PROVEN
```

---

## Historical Report Reading Note

These reports describe earlier, more local blockers. They are useful historical context, not the current main plan:

```text
misc/reports/b6.7.3e0b.2a-bootstrap-convergence-first-run.txt
misc/reports/b6.7.3e0b.2b-minimal-root-capability-audit.md
misc/reports/b6.7.3e0b.2c-empirical-capability-audit.md
misc/reports/b6.7.3e0b.2d-minimal-fix-boundary-audit.md
misc/reports/b6.7.3e0b.2e-implementation-contract.md
```

Their `std.io.eprintln`, probe_08, and "about 50 lines in `analyzer.c`" content should now be read as historical context. B6.7.1 / B6.7.2 / B6.7.3b / B6.7.3c moved qualified import/name resolution into the canonical semantic path.

---

## Current Working Statement

> S has moved past the early qualified-name blocker; the current Bootstrap problem has upgraded from "the seed lacks syntax/name-resolution capability" to "whether the Stage1 canonical implementation truly becomes the build authority."

Next work should be evidence-driven work on the M1 authority chain, not more probe_08/probe_09 or seed-level surface blocker patches.
