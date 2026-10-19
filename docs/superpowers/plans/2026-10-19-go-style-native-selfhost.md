# Go-style Native Self-hosting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make S produce and validate `Seed → Stage1 → Stage2 → Stage3 → Fixed-point` using S's own frontend, MIR, SSA, and native backend.

**Architecture:** Keep `src/cmd/dist` as the sole bootstrap coordinator. Make source closure and stage artifacts deterministic and auditable, then clear actual compiler FIRST REDs one at a time. Reuse Go's staged-build principles without copying Go compiler implementation.

**Tech Stack:** POSIX shell, Make, C Seed compiler, S compiler, ELF/binutils, existing S test scripts.

**Spec:** `docs/superpowers/specs/2026-10-19-go-style-native-selfhost-design.md`

## Global Constraints

- The normative chain is exactly `Seed → Stage1 → Stage2 → Stage3 → Fixed-point`.
- Preserve the complete production source closure; do not skip files or use stale binaries.
- Do not change frozen Pipeline Top-Level Control Phase 1 without direct bootstrap evidence.
- Do not claim a later gate before the earlier gate has a real artifact and runtime verification.
- Keep Production Authority (AST → MIR → SSA → Native ELF) as an independent report.

## Review Focus

- Closure completeness and deterministic ordering: regression test must detect missing, duplicate, test-only, or nondeterministically ordered sources.
- Stage boundary provenance: regression test must reject missing/empty artifacts and metadata that names the wrong producer.
- Seed and Stage1 diagnostics: regression test must preserve the first compiler error with file and line.
- Resource pressure: Stage2/Stage3 runs must record peak RSS and fail explicitly on timeout/OOM.
- Fixed-point semantics: regression test must compare normalized artifacts only under an explicit normalization contract.

### Task 1: Capture the current P0 baseline

**Files:**
- Create: `test/native-bootstrap-diagnostic/go_style_baseline.sh`
- Modify: `src/cmd/dist/native-bootstrap-no-manifest.sh` only if required for stable diagnostic output

**Interfaces:**
- Consumes: `bin/s_seed`, `source_closure.sh`, the production entry `src/cmd/compile/main.s`.
- Produces: reproducible baseline log containing closure count, exit code, FIRST RED, elapsed time, and RSS.

- [ ] Write a failing baseline test that runs the normative entry and asserts Stage1 is not reported successful when its IR/ELF is absent.
- [ ] Run it and record the current failure without changing source selection.
- [ ] Add only diagnostic capture needed to make the failure evidence stable.
- [ ] Re-run and verify the baseline identifies the actual first compiler error.

### Task 2: Make production source closure deterministic and auditable

**Files:**
- Modify: `src/cmd/dist/source_closure.sh`
- Create: `test/native-bootstrap-diagnostic/source_closure_contract.sh`
- Modify: `makefile` to expose a check target if needed

**Interfaces:**
- Consumes: entry source, package declarations, `import`/`use` edges.
- Produces: sorted unique `stage1.sources` plus closure metadata; production mode rejects test-only dependencies.

- [ ] Add tests for complete closure emission, duplicate removal, stable ordering, and test-only rejection.
- [ ] Run the tests to establish failures for any current contract violations.
- [ ] Implement deterministic closure traversal and explicit diagnostics without prefix-based package guessing.
- [ ] Verify closure count, source hashes, and repeatability across two runs.

### Task 3: Repair the first real Seed-to-Stage1 compiler boundary

**Files:**
- Modify only the source or compiler component named by the current FIRST RED.
- Add or modify the smallest relevant test under `test/native-bootstrap-diagnostic/`.

**Interfaces:**
- Consumes: the full Task 2 production closure.
- Produces: non-empty Stage1 IR and a native Stage1 ELF produced solely by `bin/s_seed`.

- [ ] Add the smallest regression fixture for the current FIRST RED.
- [ ] Verify the fixture fails before the fix.
- [ ] Implement one root-cause fix only.
- [ ] Run the fixture and the full Stage1 compile; record exit code, elapsed time, RSS, IR size, ELF size, and runtime smoke result.
- [ ] Repeat Task 3 for each newly exposed FIRST RED until Stage1 is executable; do not bundle unrelated parser, MIR, SSA, or backend changes.

### Task 4: Promote Stage1 to Stage2 with provenance checks

**Files:**
- Modify: `src/cmd/dist/native-bootstrap-no-manifest.sh`
- Create/modify: `test/native-bootstrap-diagnostic/stage_boundary_check.sh`

**Interfaces:**
- Consumes: Stage1 ELF and the exact Stage1 closure.
- Produces: Stage2 IR/ELF plus metadata proving Stage1 was the producer.

- [ ] Add a boundary test that rejects fallback to Seed or stale artifacts.
- [ ] Implement explicit producer identity, input hashes, output hashes, timing, and peak RSS.
- [ ] Run Stage1 → Stage2 using the same closure and verify Stage2 executes.

### Task 5: Build Stage3 and define fixed-point comparison

**Files:**
- Modify: `src/cmd/dist/native-bootstrap-no-manifest.sh`
- Create/modify: `test/native-bootstrap-diagnostic/fixed_point_check.sh`

**Interfaces:**
- Consumes: Stage2 ELF and identical closure.
- Produces: Stage3 IR/ELF and a fixed-point report.

- [ ] Add tests for identical input closure, target identity, normalized ELF comparison, and behavior smoke tests.
- [ ] Implement timeout/OOM reporting and explicit normalization rules for nondeterministic ELF fields.
- [ ] Run Stage2 → Stage3 and verify fixed-point status; report failure rather than weakening comparison.

### Task 6: Report Production Authority separately

**Files:**
- Create: `docs/reports/native-selfhost-<date>.md`
- Use existing P4 audit scripts; modify only when evidence shows a missing authoritative edge.

**Interfaces:**
- Consumes: Stage artifacts and existing MIR/SSA/native backend probes.
- Produces: separate report of AST → MIR → SSA → Native ELF authority, clearly distinct from bootstrap status.

- [ ] Run the relevant production handoff checks after Stage1 is real.
- [ ] Record remaining gaps without converting them into bootstrap PASS.
- [ ] Run the complete verification suite and publish exact results.

