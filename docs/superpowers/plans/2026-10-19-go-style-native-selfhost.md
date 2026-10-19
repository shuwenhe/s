# Go-style Native Self-hosting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Make S produce and validate `Seed → Stage1 → Stage2 → Stage3 → Fixed-point` using S's own frontend, MIR, SSA, and native backend.

**Architecture:** Keep `src/cmd/dist` as the sole bootstrap coordinator. First prove the production entry and deterministic closure, then clear actual FIRST REDs one at a time. Every gate requires independent review and fresh evidence before the next task starts.

**Tech Stack:** POSIX shell, Make, C Seed compiler, S compiler, ELF/binutils, existing S test scripts.

**Spec:** `docs/superpowers/specs/2026-10-19-go-style-native-selfhost-design.md`

## Global Constraints

- The normative chain is exactly `Seed → Stage1 → Stage2 → Stage3 → Fixed-point`.
- Preserve the complete production source closure; do not skip files or use stale binaries.
- Do not change frozen Pipeline Top-Level Control Phase 1 without direct bootstrap evidence.
- Do not claim a later gate before the earlier gate has a real artifact and runtime verification.
- Keep Production Authority (AST → MIR → SSA → Native ELF) as an independent report.
- A subagent may not advance the gate; only the coordinator accepts the evidence and assigns the next task.

## Review Focus

- Closure completeness and deterministic ordering: tests must detect missing, duplicate, test-only, or nondeterministically ordered sources under the explicit production rule.
- Entry correctness: tests must prove `main.s` reaches `compile.driver.driver_main` and that the emitted closure contains the actual production dependency graph.
- Stage boundary provenance: tests must reject fallback to Seed or stale artifacts using producer SHA-256 and command evidence.
- Resource pressure: Stage2/Stage3 runs must record peak RSS and fail explicitly on timeout/OOM.
- Fixed-point semantics: tests must preserve original artifacts and reject unknown ELF differences; only the documented field normalization may be used.

### Task 1: Capture and review the current P0 baseline

**Files:**
- Create: `test/native-bootstrap-diagnostic/go_style_baseline.sh`
- Modify: `src/cmd/dist/native-bootstrap-no-manifest.sh` only if required for stable diagnostic output

**Interfaces:**
- Consumes: `bin/s_seed`, `source_closure.sh`, `src/cmd/compile/main.s`.
- Produces: baseline log with verified entry call chain, closure count/hash, exit code, current FIRST RED, elapsed time, and RSS.

- [ ] Write a failing baseline test that proves the entry call chain and asserts Stage1 is not successful when IR/ELF is absent.
- [ ] Run it and record the current `bootstrap_demo.s:16:9` FIRST RED without changing source selection.
- [ ] Add only diagnostic capture needed for stable command, producer, timing, RSS, and failure output.
- [ ] Independent reviewer checks that no later gate is implied by the baseline.

### Task 2: Make production source closure deterministic and auditable

**Files:**
- Modify: `src/cmd/dist/source_closure.sh`
- Create: `test/native-bootstrap-diagnostic/source_closure_contract.sh`
- Modify: `makefile` to expose a check target if needed

**Interfaces:**
- Consumes: entry source, package declarations, `import`/`use` edges.
- Produces: sorted unique `stage1.sources`, closure metadata, and explicit failure for a reachable test-only dependency.

- [ ] Add tests for the explicit production rule: `.s` under `src/`, exclude `_test.s` and `testdata/`, retain non-test production files such as `bootstrap_demo.s`, and reject reachable test-only packages.
- [ ] Run tests to establish failures for current contract violations.
- [ ] Implement deterministic traversal, explicit package/path mapping, and diagnostics without prefix-only matching.
- [ ] Verify two runs have identical ordered lists and hashes; independent reviewer checks the count and sample membership.

### Task 3: Repair the first real Seed-to-Stage1 compiler boundary

**Files:**
- Modify only the source or compiler component named by the current FIRST RED.
- Add or modify the smallest relevant test under `test/native-bootstrap-diagnostic/`.

**Interfaces:**
- Consumes: the full Task 2 production closure.
- Produces: non-empty Stage1 IR and native Stage1 ELF produced solely by `bin/s_seed`.

- [ ] Add the smallest regression fixture for the current FIRST RED.
- [ ] Verify the fixture fails before the fix.
- [ ] Implement one root-cause fix only.
- [ ] Run the fixture and full Stage1 compile; record command, producer hash, exit code, elapsed time, peak RSS, IR/ELF size/hash, and runtime smoke result.
- [ ] Independent reviewer verifies the artifact producer is `bin/s_seed` and that no later stage is claimed.
- [ ] Repeat only this task for each newly exposed FIRST RED until Stage1 is executable.

### Task 4: Promote Stage1 to Stage2 with provenance checks

**Files:**
- Modify: `src/cmd/dist/native-bootstrap-no-manifest.sh`
- Create/modify: `test/native-bootstrap-diagnostic/stage_boundary_check.sh`

**Interfaces:**
- Consumes: Stage1 ELF and the exact Stage1 closure.
- Produces: Stage2 IR/ELF plus metadata proving Stage1 was the producer.

- [ ] Add a boundary test that rejects fallback to Seed, wrong producer SHA-256, stale closure hash, or stale output.
- [ ] Implement producer identity, input/output hashes, actual command, timing, exit code, and peak RSS.
- [ ] Run Stage1 → Stage2 using the same closure and verify Stage2 executes.
- [ ] Independent reviewer accepts P1 only from fresh artifacts and logs.

### Task 5: Build Stage3 and enforce fixed-point comparison

**Files:**
- Modify: `src/cmd/dist/native-bootstrap-no-manifest.sh`
- Create/modify: `test/native-bootstrap-diagnostic/fixed_point_check.sh`

**Interfaces:**
- Consumes: Stage2 ELF and byte-identical ordered closure.
- Produces: Stage3 IR/ELF and a fixed-point report retaining original artifacts.

- [ ] Add tests for identical closure, target identity, raw ELF comparison, documented normalization fields only, and smoke behavior.
- [ ] Implement timeout/OOM reporting and the explicit normalization contract; unknown ELF differences fail.
- [ ] Run Stage2 → Stage3 and verify fixed-point status with both raw and normalized hashes.
- [ ] Independent reviewer accepts P3 only when raw/normalized differences are fully explained.

### Task 6: Report Production Authority separately

**Files:**
- Create: `docs/reports/native-selfhost-<date>.md`
- Use existing P4 audit scripts; modify only when evidence shows a missing authoritative edge.

**Interfaces:**
- Consumes: Stage artifacts and existing MIR/SSA/native backend probes.
- Produces: separate report of AST → MIR → SSA → Native ELF authority, clearly distinct from bootstrap status.

- [ ] Run relevant production handoff checks after Stage1 is real.
- [ ] Record remaining gaps without converting them into bootstrap PASS.
- [ ] Run the complete verification suite and publish exact results.
- [ ] Independent reviewer checks the final report against all gate evidence.

