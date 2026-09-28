# Stage1 Canonical Build Authority Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove by real execution that Stage1 `build` enters the canonical modular compiler path and produces a native Stage2 artifact.

**Architecture:** Keep Stage0 as the one-time lifter, but change the generated Stage1 `build` runtime path from `bootstrap_subset_build` to a generated canonical build entry. Strengthen the checks so they require actual Stage1 execution evidence: canonical entry reached, `modular_build_main.main` reached, `backend_elf64.build` reached, bootstrap subset not reached, and a native Stage2 artifact produced.

**Tech Stack:** C Stage0 generator, S compiler sources, POSIX shell checks, GNU Make bootstrap targets, Linux/amd64 native artifacts.

**Spec:** `docs/superpowers/specs/2026-09-28-stage1-canonical-build-authority-handoff-design.md`

## Global Constraints

- Do not expand the seed parser, seed semantic analyzer, or seed name resolver.
- Do not add language coverage to `bootstrap_subset_build`.
- Do not rename `bootstrap_subset_build` to a canonical-sounding function while still executing the same subset path.
- Do not work on Stage2/Stage3 convergence before Stage1 canonical entry linkage is proven.
- Do not refactor the canonical backend except for a minimal direct proof hook needed to expose real execution.
- Passing evidence must come from real Stage1 execution, not source grep, closure metadata, embedded strings, or marker-only checks.

## Review Focus

- Stage1 `build` can still execute `bootstrap_subset_build`; checks must fail when `bootstrap-subset:` appears in runtime output.
- Stage1 can embed canonical closure without executing it; checks must require a runtime invocation proof.
- Stage1 can hardcode a fixture artifact; checks must build a canonical input path and validate the produced artifact is native and executable.
- A generated function can be named canonical while calling subset code; checks must identify the reached canonical entry and backend path separately.
- Stage2 artifact can be a wrapper/text/prebuilt copy; checks must reject shell scripts, text executables, and unchanged prebuilt artifacts.

---

## File Structure

- `src/cmd/compile/stage0/stage0.c`: owns Stage1 C generation and the Stage1 command dispatch emitted by Stage0.
- `src/cmd/compile/modular_build_main.s`: owns the canonical modular CLI entry and dispatches `build` to `compile.internal.backend_elf64.build`.
- `src/cmd/compile/internal/backend_elf64.s`: owns canonical native build execution and may expose a minimal proof line when reached.
- `misc/scripts/stage1-canonical-entry-linkage-check.sh`: proves Stage1 links and calls the generated canonical entry by running Stage1.
- `misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh`: proves Stage1 `build` no longer routes through the bootstrap subset and reaches canonical compiler authority.
- `misc/scripts/stage1-build-authority-check.sh`: remains the static/structural companion check for the intended replacement edge.
- `makefile`: only updated if a target needs to pass a new report/output path into existing checks.

## Task 1: Baseline The Real Stage1 Dispatch And Canonical Entry Gap

**Files:**
- Modify: `misc/scripts/stage1-canonical-entry-linkage-check.sh`
- Report output: `.bootstrap/modular/stage1-canonical-entry-linkage-report.txt`

**Interfaces:**
- Consumes: `.bootstrap/modular/s_modular-stage1` from `make modular-bootstrap`
- Produces: report fields consumed by later tasks:
  - `stage1-build-runtime-status=<int>`
  - `bootstrap-subset-runtime-path=YES|NO`
  - `generated-canonical-entry-reached=YES|NO`
  - `modular-build-main-reached=YES|NO`
  - `canonical-backend-build-reached=YES|NO`
  - `native-stage2-artifact=YES|NO`
  - `stage1-canonical-entry-linkage=PROVEN|NOT_PROVEN`

- [ ] **Step 1: Add a failing runtime proof check**

Update `misc/scripts/stage1-canonical-entry-linkage-check.sh` so it runs:

```sh
S_PROJECT_ROOT="$root" S_SOURCE_ROOT="$root/src" \
  "$stage1" build src/cmd/compile/modular_build_main.s -o "$tmp/stage2"
```

The script must capture stdout/stderr into `$tmp/stage1-build.log`, inspect the produced `$tmp/stage2`, and write all report fields listed in this task's Interfaces block.

- [ ] **Step 2: Run the check and verify current failure**

Run: `make stage1-canonical-entry-linkage-check`

Expected: FAIL with `stage1-canonical-entry-linkage=NOT_PROVEN`, `bootstrap-subset-runtime-path=YES`, and `native-stage2-artifact=NO`.

- [ ] **Step 3: Add false-positive rejection**

In the same script, ensure the verdict remains `NOT_PROVEN` if any of these are true:

```text
bootstrap-subset-runtime-path=YES
generated-canonical-entry-reached=NO
modular-build-main-reached=NO
canonical-backend-build-reached=NO
native-stage2-artifact=NO
```

- [ ] **Step 4: Re-run the check**

Run: `make stage1-canonical-entry-linkage-check`

Expected: FAIL for the same real authority gap, not because the script is broken.

- [ ] **Step 5: Commit**

```sh
git add misc/scripts/stage1-canonical-entry-linkage-check.sh
git commit -m "test: require real stage1 canonical entry execution"
```

## Task 2: Define The Generated Canonical Entry ABI

**Files:**
- Modify: `src/cmd/compile/stage0/stage0.c`
- Modify: `misc/scripts/stage1-build-authority-check.sh`

**Interfaces:**
- Produces C symbol in generated Stage1:
  - `static int generated_canonical_build_entry(const char *input, const char *output)`
- Produces runtime evidence lines on Stage1 execution:
  - `stage1-trace: generated-canonical-entry`
  - `stage1-trace: modular_build_main.main`
  - `stage1-trace: backend_elf64.build`

- [ ] **Step 1: Add structural expectations to the authority check**

Update `misc/scripts/stage1-build-authority-check.sh` so the intended replacement edge requires the generated Stage1 C to contain:

```text
generated_canonical_build_entry
stage1-trace: generated-canonical-entry
stage1-trace: modular_build_main.main
stage1-trace: backend_elf64.build
```

The check must still fail if the generated Stage1 `build` handler is `bootstrap_subset_build`.

- [ ] **Step 2: Run the structural check and verify failure**

Run: `make stage1-build-authority-check`

Expected: FAIL with missing generated canonical entry ABI evidence.

- [ ] **Step 3: Add the generated entry stub without dispatching to it**

In `write_stage1_c(FILE *out, const ClosureStats *stats)` in `src/cmd/compile/stage0/stage0.c`, emit:

```c
static int generated_canonical_build_entry(const char *input, const char *output);
```

and a definition with the exact signature. For this task only, the function may return failure after emitting the trace lines; do not wire Stage1 `build` to it yet.

- [ ] **Step 4: Run modular bootstrap and structural check**

Run: `make modular-bootstrap`

Expected: PASS and generated `.bootstrap/modular/s_modular-stage1.c` contains the new symbol.

Run: `make stage1-build-authority-check`

Expected: still FAIL because Stage1 `build` is not dispatched to the generated canonical entry yet.

- [ ] **Step 5: Commit**

```sh
git add src/cmd/compile/stage0/stage0.c misc/scripts/stage1-build-authority-check.sh
git commit -m "test: define generated canonical build entry ABI"
```

## Task 3: Wire Stage1 Build Dispatch To The Generated Canonical Entry

**Files:**
- Modify: `src/cmd/compile/stage0/stage0.c`
- Modify: `misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh`

**Interfaces:**
- Consumes: `generated_canonical_build_entry(const char *input, const char *output)` from Task 2
- Produces: Stage1 `build` dispatch:
  - validates `argc == 5`
  - validates `argv[3] == "-o"`
  - calls `generated_canonical_build_entry(argv[2], argv[4])`

- [ ] **Step 1: Strengthen authority handoff check**

Update `misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh` so it classifies GREEN only when runtime output has:

```text
stage1-trace: generated-canonical-entry
stage1-trace: modular_build_main.main
stage1-trace: backend_elf64.build
```

and lacks:

```text
bootstrap-subset:
```

- [ ] **Step 2: Run authority handoff check and verify failure**

Run: `bash misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh`

Expected: FAIL with `bootstrap-subset-runtime-path=YES` before dispatch is rewired.

- [ ] **Step 3: Replace only the Stage1 build dispatch**

In the generated main body emitted by `src/cmd/compile/stage0/stage0.c`, replace the emitted Stage1 `build` branch:

```c
return bootstrap_subset_build(argv[2], argv[4]);
```

with:

```c
return generated_canonical_build_entry(argv[2], argv[4]);
```

Do not delete `bootstrap_subset_build` in this task; the purpose is to prove dispatch no longer reaches it.

- [ ] **Step 4: Run modular bootstrap and handoff check**

Run: `make modular-bootstrap`

Expected: PASS.

Run: `bash misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh`

Expected: FAIL until Task 4 implements real canonical behavior, but `bootstrap-subset-runtime-path=NO` and `stage1-generated-build-handler=canonical_build`.

- [ ] **Step 5: Commit**

```sh
git add src/cmd/compile/stage0/stage0.c misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh
git commit -m "feat: dispatch stage1 build to generated canonical entry"
```

## Task 4: Connect Generated Entry To The Canonical Modular Build Path

**Files:**
- Modify: `src/cmd/compile/stage0/stage0.c`
- Modify: `src/cmd/compile/modular_build_main.s` only if a minimal proof hook is needed
- Modify: `src/cmd/compile/internal/backend_elf64.s` only if a minimal proof hook is needed

**Interfaces:**
- Consumes: `generated_canonical_build_entry(const char *input, const char *output)`
- Produces: a Stage1 runtime path whose trace proves:
  - generated canonical entry reached
  - modular build main reached
  - backend build reached

- [ ] **Step 1: Add a canonical entry execution test through the existing check**

Run: `make stage1-canonical-entry-linkage-check`

Expected: FAIL with `generated-canonical-entry-reached=YES`, `bootstrap-subset-runtime-path=NO`, but `modular-build-main-reached=NO` or `canonical-backend-build-reached=NO`.

- [ ] **Step 2: Implement the minimal generated canonical entry body**

In `src/cmd/compile/stage0/stage0.c`, implement `generated_canonical_build_entry(const char *input, const char *output)` so it follows the canonical modular build path represented by the embedded closure. It must not call `bootstrap_subset_build`.

The implementation choice is constrained by the current Stage0 architecture:

```text
input/output CLI -> generated canonical entry
generated canonical entry -> modular_build_main-equivalent dispatch
modular_build_main-equivalent dispatch -> backend_elf64.build-equivalent execution
```

If direct S symbol lowering is not available yet, emit a minimal generated bridge from the canonical closure for `modular_build_main.main` and `backend_elf64.build`; do not introduce a general bootstrap subset compiler.

- [ ] **Step 3: Expose proof lines from the real path**

Ensure the runtime log includes these exact lines only when the corresponding path is actually executed:

```text
stage1-trace: generated-canonical-entry
stage1-trace: modular_build_main.main
stage1-trace: backend_elf64.build
```

If proof hooks are added in `.s` files, keep them behind the existing Stage1/bootstrap execution path and do not alter normal compiler output semantics.

- [ ] **Step 4: Rebuild and run linkage check**

Run: `make modular-bootstrap`

Expected: PASS.

Run: `make stage1-canonical-entry-linkage-check`

Expected: FAIL only if no native Stage2 artifact is produced yet. It must report `generated-canonical-entry-reached=YES`, `modular-build-main-reached=YES`, `canonical-backend-build-reached=YES`, and `bootstrap-subset-runtime-path=NO`.

- [ ] **Step 5: Commit**

```sh
git add src/cmd/compile/stage0/stage0.c src/cmd/compile/modular_build_main.s src/cmd/compile/internal/backend_elf64.s
git commit -m "feat: connect stage1 generated entry to canonical build path"
```

## Task 5: Produce And Validate Native Stage2 From Stage1 Canonical Build

**Files:**
- Modify: `src/cmd/compile/stage0/stage0.c`
- Modify: `misc/scripts/stage1-canonical-entry-linkage-check.sh`
- Modify: `misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh`

**Interfaces:**
- Consumes: canonical path proof from Task 4
- Produces: native Stage2 artifact at the output path passed to Stage1 `build`

- [ ] **Step 1: Add native artifact validation**

In both runtime checks, validate the Stage2 output with:

```sh
test -x "$stage2"
file "$stage2" | grep -Eq 'ELF|Mach-O'
! file "$stage2" | grep -Eiq 'shell script|text executable'
! cmp -s "$stage2" "$root/bin/s_seed"
! cmp -s "$stage2" "$stage1"
```

Use the platform's expected native format from existing target config where available.

- [ ] **Step 2: Run checks and verify native artifact failure**

Run: `make stage1-canonical-entry-linkage-check`

Expected: FAIL with canonical path reached but `native-stage2-artifact=NO` if artifact production is still missing.

- [ ] **Step 3: Implement native Stage2 emission through canonical backend**

Complete the generated canonical path so `backend_elf64.build` writes the output requested by Stage1 `build`. The output must be produced by the canonical backend path, not by a hardcoded fixture, template-only artifact, shell wrapper, or copied prebuilt file.

- [ ] **Step 4: Run the three P0 gates**

Run: `make stage1-build-authority-check`

Expected: PASS with `stage1-build-authority=PASS` or the script's equivalent PASS verdict.

Run: `make stage1-canonical-entry-linkage-check`

Expected: PASS with `stage1-canonical-entry-linkage=PROVEN`, `native-stage2-artifact=YES`, and no bootstrap subset runtime path.

Run: `bash misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh`

Expected: PASS with `classification=B6.7.3e_GREEN`.

- [ ] **Step 5: Commit**

```sh
git add src/cmd/compile/stage0/stage0.c misc/scripts/stage1-canonical-entry-linkage-check.sh misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh
git commit -m "feat: produce native stage2 from stage1 canonical build"
```

## Task 6: Final P0 Regression Guard

**Files:**
- Modify: `makefile` only if needed to compose an existing target
- Modify: `misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh`
- Modify: `misc/scripts/stage1-canonical-entry-linkage-check.sh`

**Interfaces:**
- Consumes: all report fields from Tasks 1-5
- Produces: stable P0 regression workflow:
  - `make stage1-build-authority-check`
  - `make stage1-canonical-entry-linkage-check`
  - `bash misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh`

- [ ] **Step 1: Add anti-regression assertions**

Ensure the checks explicitly fail if any runtime log contains:

```text
bootstrap-subset:
artifact-only:
canonical-source-compilation=NOT_PROVEN
production-compiler-bootstrap=NOT_PROVEN
```

for the Stage1 canonical build path.

- [ ] **Step 2: Run P0 gates from clean generated state**

Run: `rm -rf .bootstrap/modular`

Run: `make stage1-build-authority-check`

Expected: PASS.

Run: `make stage1-canonical-entry-linkage-check`

Expected: PASS.

Run: `bash misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh`

Expected: PASS.

- [ ] **Step 3: Run production check only as a non-P0 signal**

Run: `make production-selfhost-check`

Expected: It may still report broader production authority gaps. Do not expand this plan to Stage2/Stage3 convergence unless the only remaining failure is the P0 handoff already covered above.

- [ ] **Step 4: Commit**

```sh
git add makefile misc/scripts/stage1-canonical-entry-linkage-check.sh misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh
git commit -m "test: guard stage1 canonical authority handoff"
```

## Self-Review

- Spec coverage: The plan covers Stage1 dispatch, generated canonical entry, canonical backend reachability, native Stage2 artifact, and false-positive rejection. It intentionally excludes Stage2/Stage3 convergence per spec.
- Step scan: Each task has one deliverable and one verification cycle. Task 4 leaves implementation choice open only where the current Stage0 architecture determines what is possible after P0.1 evidence.
- Type consistency: The generated C ABI is consistently `static int generated_canonical_build_entry(const char *input, const char *output)`.
- Review Focus: Each listed failure mode is pinned to checks in Tasks 1, 3, 5, or 6.
- Proportion: The plan is longer than the spec because it names exact files, report fields, commands, and failure modes, but it avoids writing the implementation body.
