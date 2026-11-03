# Reproducible Clean-Room Self-Hosting Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan sequentially.

**Goal:** Prove a newly committed, isolated checkout builds fresh C Seed → Stage1 → Stage2 → Stage3 with exact convergence and regressions.
**Architecture:** Keep all prior evidence. Freeze the verified source first; a committed Python controller creates a local no-hardlinks clone of an exact revision, rejects nonempty output directories, builds every stage anew, measures commands, verifies source identities and retains all output. CI invokes that same controller without caches. Compiler implementation stays unchanged unless a reproducible correctness failure requires a fix.
**Tech Stack:** Python standard library, Git, GNU make/GCC/binutils, Linux/amd64, GitHub Actions.
**Spec:** doc/superpowers/specs/2026-11-03-cleanroom-selfhost.md

## Global Constraints

- No speculative optimization, syntax or ABI changes.
- No checkpoint reuse, cached objects or source mutation during acceptance.
- Preserve all previous evidence and failed attempts.
- Do not signal existing processes; the controller never kills processes.
- Report PASS, FAIL, BLOCKED and NOT RUN accurately.

## Review Focus

- Nonempty output directories or inherited compiler/runtime override variables must not permit reuse.
- A failed command or changed source must preclude acceptance and retain logs.
- Source closure order, exact bytes, reachable function labels and entry points must be checked independently.
- CI must use fresh builds and upload failure evidence, with no claimed remote success without an actual run.
- Standard-library coverage must name exact packages and distinguish unsupported packages from successful application builds.

### Task 1: Freeze verified source (Phase 1)
- [x] Inspect branch/index/worktree, existing evidence and required tracked files.
- [x] Run complete core production regressions against installed verified compiler; retain command, exit, duration, RSS and hashes.
- [x] Commit mission spec, plan and source-verification receipt. Record exact revision and 268-file ordered closure hashes.

### Task 2: Clean-room controller (Phases 2–3)
**Files:** misc/scripts/cleanroom-selfhost.py; test/bootstrap-reproducibility/test_cleanroom.py; doc/selfhost-verification/cleanroom.md.
**Interface:** --repository PATH --revision SHA --output NEW_PATH [--mode full|core]. No resume option. Exact revision is cloned locally without hardlinks. All commands run in the clean checkout, with separate build/evidence directories.
- [x] Write behavioral tests for fresh clone isolation, dirty source rejection, reuse refusal, environment sanitation, failure logging, source drift, byte comparison and function-label mismatch; observe RED.
- [x] Implement minimum controller, manifest, per-command stdout/stderr/time/RSS/output-hash receipts and closure/source integrity checks; observe GREEN.
- [ ] Commit controller/tests before freezing the clean-room revision.
- [ ] Run full fresh chain; on failure preserve attempt, fix tested cause, commit and restart in a new directory.
- [ ] Verify all stages, production regressions using stage3 and exact Stage2/Stage3 assembly/ELF equality.

### Task 3: CI (Phase 4)
**Files:** .github/workflows/selfhost.yml; misc/scripts/ci-core.sh.
- [ ] Add per-push/PR core-production gates and scheduled/manual cache-free full clean-room bootstrap, always uploading evidence.
- [ ] Validate CI YAML and execute the same local core entrypoint. Remote execution remains NOT RUN unless authorized/available.
- [ ] Commit workflow and validation evidence; preserve the frozen bootstrap checkout unchanged.

### Task 4: Real usage and final audit (Phase 5)
**Files:** test/real-world-selfhost/; doc/selfhost-verification/cleanroom-2026-11-03.md.
- [ ] Use fresh stage3 to compile actual stdlib packages and representative imported multi-file applications, including generics/methods/records/arrays/tuples/results and native C ABI.
- [ ] Record explicit package coverage and reproducible failures; fix correctness failures before performance work.
- [ ] Independently review whole change, verify evidence/source/artifact hashes and status checklist, commit final report.

## Current mission addendum

Main only; baseline c8448bcb8. Final source must retain strict instantiated-type descriptors, preflight and pin ripgrep, expose actual process heartbeat/CPU/RSS/function/diagnostic metrics, make Stage3 compile the full closure itself, run every production recipe with retained traces, and pass both local and GitHub full acceptance on the frozen commit. Authoring CI is preparation; local and remote acceptance remain separate NOT RUN statuses until their actual fresh commands pass. All previous evidence remains preserved.
