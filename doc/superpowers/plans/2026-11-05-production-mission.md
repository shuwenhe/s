# Production mission implementation plan

**Goal:** Complete the attached final engineering mission without weakening frozen acceptance.
**Spec:** `doc/production-readiness/mission.md` and the user's final engineering mission.
**Architecture:** Retain canonical frontend/MIR/SSA/AMD64 and the existing clean-room controller. Fix reproducible defects first; ship a relocatable driver/compiler/source bundle with explicit support limits and fail-closed certification.
**Execution:** Autonomous, inline. The user explicitly requests continued execution; routine design and implementation choices do not require another approval.

## Constraints and review focus

- Preserve all historical evidence and snapshots; use fresh output directories.
- No semantic change without a regression. No push, publishing or fabricated acceptance.
- Guard source/output inode aliases in every compiler entry mode.
- Installation must work outside the repository, including paths containing spaces.
- Failed builds and malformed CLI commands must preserve prior output and sources.
- Release artifacts must identify their exact source/compiler and reject incomplete acceptance.
- Library source presence does not establish working native support.

## Tasks

1. Baseline: independently inspect Git/CI/artifacts; run unchanged full acceptance at f8cbb4e00541dd464cf8b2906ba2d904333a072a. Retain logs in `/root/shuwen/s-mission-20261105-full`.
2. P0 diagnostic source overwrite: add `test/cli/test_native_output_alias.py`, demonstrate failures for direct/symlink/hardlink/directory aliases across emit and unit commands. Add one shared guard to `src/cmd/compile/internal/compiler/main.s`; run targeted tests, production and native ABI suite; commit together.
3. Distribution CLI: add version identification, run and executable-file tests to the tracked shell driver; keep native build authority and explicitly exclude formatter until implemented. Test failure propagation and temporary cleanup. Align installed and checkout interfaces.
4. Distribution packaging: deterministic source/runtime/library layout, installer/uninstaller, artifact manifest and clean-directory smoke test. Require full same-revision acceptance before certification. Retain unsigned candidates separately.
5. Audit: produce all seven requested top-level documents, with explicit supported/unsupported language and standard-library evidence, severity and acceptance criteria for all 17 requested areas. Add reproducible malformed-input fuzz and performance reports.
6. Certification: commit logical increments, run final-revision production/ABI/memory/stdlib/installation tests and fresh full bootstrap, generate artifacts/checksums, review; obtain authorization only for the final external CI push/dispatch if still required.

## Ledger

- Initial tree clean, main at f8cbb4e00, formatting-only AST diff from frozen 1e7d36d64.
- GitHub run 41789234741 independently returned core/full success; artifacts associate it with exact frozen SHA and are unexpired.
- Restricted tracing probe failed; approved escalated probe succeeded. Full unchanged controller running with 21/21 policy tests passing.
- P0 reproduced: `--emit-mir source source` exits 0 and destroys source. Root cause: general compiler modes call write_text_file without the same-file guard used by native_build.
- User correction: develop only on main; no feature branches or branch-based worktrees. Switched back to main with all changes preserved; the temporary branch had no unique commits, was confirmed already merged, and was removed. Clean-room controller uses its own detached clone for verification only.
- P0 output guard: 21 failing alias cases before, complete targeted suite after PASS. Rebuilt compiler; complete production command `make -o compiler selfhost-canonical-production-check` exited 0 (s-mission-p0-production.log). Final-revision bootstrap still required.
- ABI regression initially failed even with fresh unchanged baseline seed: stale fixture omitted records/globals/field_names and real MIR reference helpers. Restored actual dependencies; complete native-codegen/check.sh exits 0, all original assertions retained.
- CLI red/green: missing version/run/test reproduced, now 4/4 tests PASS. Relocation, unowned-file preservation and library-only upgrades 3/3 PASS. Packaging reproducibility and missing-license rejection 2/2 PASS.
- Owner license choice requested asynchronously; official redistribution remains blocked. No license invented.
- Fuzz initial probe exposed diagnostic MIR errors returned as successful text. Canonical public MIR/unit modes reject the same unknown-name input. Diagnose the diagnostic-mode exit contract before changing it; retained initial corpus/report.
