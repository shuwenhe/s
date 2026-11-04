# Production engineering ledger

Mission active; production readiness is not established.
Baseline: 35fae2bf820957cea2837b8ca316cdec77d2cd39, initial clean tree.
Work branch: production-readiness-20261104. Historical evidence is untouched.
Fresh evidence directory: /app/shuwen/production-mission-20261104.

## Decisions
- Execute routine engineering autonomously as explicitly requested. Work on a dedicated branch in the existing checkout; avoid duplicating accepted build artifacts.
- Prior self-host acceptance verifies compiler convergence and selected behavior, not complete language/runtime implementation.

## Checklist
- [x] Read mission, current revision, previous acceptance report and build recipes.
- [ ] Independently validate historical evidence.
- [ ] Run fresh controller and production tests.
- [ ] Complete 20-subsystem audit.
- [ ] Resolve all P0/P1 defects with permanent regressions.
- [ ] Complete documentation and clean-checkout tutorial.
- [ ] Fresh final bootstrap and independent CI.

## Initial findings
- P3: README links doc/compiler.md, doc/native-codegen.md and doc/platforms.md do not exist. Reproduce with file existence checks; repair with accurate guides.
- Investigation: canonical SSA rejects multiple physical return values (function_lower.s:84 and program.s:519); determine established tuple-return lowering before calling this a language defect.
- Investigation: README runtime foundation explicitly requires missing target intrinsic lowering, stack maps and safe-point metadata. Audit actual native GC rather than inferring support from API declarations.

## Verification log
Pending controller run. No new bootstrap or compiler correctness claim yet.

### Baseline verification
- Fresh independent historical evidence audit: PASS (production-mission-20261104/baseline-audit/audit.json). This validates retained artifacts, not a new bootstrap.
- Fresh controller tests: 21/21 PASS with tracing enabled (controller-unrestricted.log). Restricted run failed three tracing tests; direct strace probe confirmed PTRACE_TRACEME denied. No test skipped or weakened.
- Production suite running; initial target rebuilds the seed-hosted development compiler. Historical accepted artifacts remain untouched in their separate evidence directories.

### P0-001: legacy output aliases
- Reproduction: test/cli/test_output_alias.py fails for symlink, hardlink and directory symlink output aliases; compiler exits 0 and overwrites source.
- Cause: shell legacy path compares lexical absolute paths; cp follows aliases when installing output.
- Fix: reject existing source/output inode identity with test -ef, retaining lexical guard.
- Focused regression: all four alias cases PASS after updating generated bin/s from tracked driver.
- Added explicit Python test-script recipe to production target so clean-room command inventory sees it.

### Documentation
- Added missing compiler.md, native-codegen.md and platforms.md with source-backed scope, commands and limitations.
- Initial 20-subsystem source/coverage matrix in audit.md; unverified behavior remains explicitly open.
- Full restricted production attempt failed at strace-injected interrupted-write test (ptrace denied). Full rerun with tracing enabled is running, no checks removed.

### Additional correctness findings
- P1-004: `func main() int { value := -9223372036854775808; ... }` fails with `integer literal exceeds int64: 9223372036854775808`. Unary negation lowers its positive operand before negation; minimum signed literal needs explicit handling.
- P1-005: `switch value { -1: 42, _: 1 }` fails with `unsupported integer spelling: -1`. Parser emits a signed literal for negative patterns, but program_emit_integer accepts only digits.
- P0-002: Development/Stage1 compiler silently miscompiles decimal constants outside signed 63-bit carrier range. Example: source comparison against `-7294953415784369124` emits positive-operand assembly immediate `-1928418621070406684` instead of `7294953415784369124`. Frozen Stage3 emits the correct immediate. Root cause traced to standalone seed tagged integers (`raw * 2 + 1`, arithmetic shifts/tags); full int64 arithmetic cannot fit this representation. No fix claimed.
- New 720-case deterministic differential exposed P0-002. First harness shape (one giant 720-branch function) exceeded its 120-second compile budget. Splitting assertions by operation/constant retained all 720 cases and isolated the defect to multiplication case operand 2431651138594789708, constant -3. Both logs retained. This is a test-shape improvement, not a relaxed compiler timeout.

### Completed increment: P0-001
- Commit 45d340dfd: legacy source-alias rejection plus permanent regression and production recipe.
- Focused regression rerun PASS, git diff --check PASS.
- Full production run with tracing enabled exited 0; complete log production-unrestricted.log. It includes all prior recipes plus new alias test.
- No S compiler source change in this increment; historical staged bootstrap evidence remains valid for the unchanged compiler closure. New staged rebuild not claimed.
- Frozen Stage3 passed all 720 new integer differential cases; development/Stage1 fails. Logs integer-differential-stage3.log and integer-differential-diagnostic.log.
