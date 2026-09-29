# Stage 8 CanonicalTypeRef Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the Stage 8 CanonicalTypeRef closure contract and a canonical gate that fails RED at the first unmet S8.1 contract without implementing Stage 8.

**Architecture:** Mirror Stage 6/7 closure discipline: a contract document defines S8.x proof obligations, and `scripts/canonical-type-ref-check.sh` deterministically attributes the first unmet contract. Since no real compiler `canonical-type-ref-proof` producer exists yet, the gate reports S8.1 Input Boundary as the first RED.

**Tech Stack:** POSIX shell gate scripts, project makefile, existing `bin/s_compiler` build flow, markdown contract docs.

**Spec:** `doc/stage8-canonical-type-ref-contract.md`

## Global Constraints

- Do not implement Stage 8 CanonicalTypeRef production in this milestone.
- Do not modify Stage 7 proof semantics except as required by existing uncommitted work.
- The gate must fail with `first-unmet-contract=S8.1` until a real compiler proof producer exists.
- The proof must not claim Semantic Analysis, MIR, layout, ABI, or codegen.

## Review Focus

- Missing proof producer must fail S8.1, not be reported as SKIP.
- Mock proof mode must preserve deterministic first-unmet attribution.
- Full `compile-pipeline-check` must report Stage 8 as failed gate, not missing gate.
- Stage 7 must remain PROVEN after adding the Stage 8 gate.
- No Stage 8 implementation or later-stage success claims should be introduced.

---

### Task 1: Stage 8 Contract And RED Gate

**Files:**
- Create: `doc/stage8-canonical-type-ref-contract.md`
- Create: `scripts/canonical-type-ref-check.sh`
- Create: `misc/scripts/test-stage8-canonical-type-ref-gate.sh`
- Modify: `makefile`

**Interfaces:**
- Consumes: Stage 7 `stage7-type-facts` output role from `doc/stage7-type-checking-contract.md`.
- Produces: `make canonical-type-ref-check`, report `.bootstrap/stage8/canonical-type-ref-gate.txt`, first RED `S8.1`.

- [ ] **Step 1: Write the failing directed gate test**

Create `misc/scripts/test-stage8-canonical-type-ref-gate.sh` asserting `make canonical-type-ref-check` exits 1 and report contains `S8.1 Input Boundary=FAIL`, `first-unmet-contract=S8.1`, and `stage8-canonical-type-ref=NOT_CLOSED`.

- [ ] **Step 2: Run test to verify RED**

Run: `sh misc/scripts/test-stage8-canonical-type-ref-gate.sh`
Expected: FAIL because `canonical-type-ref-check` does not exist yet.

- [ ] **Step 3: Write `doc/stage8-canonical-type-ref-contract.md`**

Define Stage 8 ownership and closure criteria around type facts -> canonical type identity, with S8.1-S8.8 matching the discovered architecture.

- [ ] **Step 4: Implement `scripts/canonical-type-ref-check.sh`**

Follow the Stage 7 gate pattern. If no real `canonical-type-ref-proof` producer exists, write raw proof with `S8.1=FAIL` and reason `no observable Stage 8 proof producer; compiler does not expose canonical-type-ref-proof`.

- [ ] **Step 5: Add `canonical-type-ref-check` make target**

Wire the gate through the makefile with dependency `compiler`.

- [ ] **Step 6: Run directed gate test**

Run: `sh misc/scripts/test-stage8-canonical-type-ref-gate.sh`
Expected: PASS.

- [ ] **Step 7: Run canonical gate directly**

Run: `make canonical-type-ref-check`
Expected: exit 1 with first-unmet S8.1.

- [ ] **Step 8: Run full pipeline**

Run: `make compile-pipeline-check`
Expected: exit 8, Stage 7 PROVEN, Stage 8 FAIL/FAILED with reason `gate canonical-type-ref-check failed`.
