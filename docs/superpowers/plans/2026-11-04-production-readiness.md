# S production readiness implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Meet the production readiness mission without weakening prior acceptance.
**Architecture:** Preserve historical evidence. Audit the canonical compiler path separately from seed and experimental paths, reproduce defects with executable tests, and fix in priority order. Record every outstanding acceptance requirement.
**Tech Stack:** S, C seed, Linux/amd64 assembly, Python controllers, shell regression scripts.
**Spec:** doc/production-readiness/mission.md

## Global constraints
- Do not introduce incompatible syntax or silently change established S language semantics.
- Never hide failures, weaken assertions, skip tests, or change expected results merely to obtain PASS.
- Never claim PASS without actual evidence.
- Preserve accepted artifacts and concurrent changes.

## Review focus
- Malformed source must fail without crashes or replacing output files.
- Side effects must execute once in source order.
- Boundary integers, indexing and allocation sizes must preserve established semantics.
- Imported declarations and generic instances must retain nominal identities.
- A clean checkout must expose the same documented supported compiler path.

### Task 1: Verify baseline and audit subsystems
- [ ] Inspect frozen revision, source closure, retained acceptance receipts and convergence hashes.
- [ ] Run controller tests and production suite with separate logs.
- [ ] Map all 20 subsystems to active source, executable coverage and gaps.
- [ ] Record prioritized reproducible defects and open investigations in doc/production-readiness/status.md.

### Task 2: Correctness engineering loop
- [ ] Reproduce each P0/P1 defect with a permanent regression test; observe failure.
- [ ] Implement the smallest correct fix and observe the regression pass.
- [ ] Run complete production suite after each significant change.
- [ ] For compiler changes, run fresh full staged clean-room bootstrap and byte comparisons.
- [ ] Commit each verified logical increment; continue backlog.

### Task 3: Language, runtime, native code and documentation
- [ ] Audit specified language features against established syntax and semantic tests.
- [ ] Exercise ABI, MIR/SSA validation, GC stress, constrained memory and differential integer cases.
- [ ] Measure compile time, RSS and representative program runtime.
- [ ] Repair installation/tutorial/CLI/runtime/FFI/specification documentation against actual tested behavior.
- [ ] Record platform and unsupported functionality precisely; resolve P1 gaps.

### Task 4: Release verification
- [ ] Complete fresh clean-room bootstrap at final compiler revision.
- [ ] Verify independent CI at exact source revision when externally authorized.
- [ ] Review final changes and run required checks.
- [ ] Produce readiness report, evidence index, checklist, benchmarks and limitations.
- [ ] Mark mission complete only when every applicable criterion is evidenced.
