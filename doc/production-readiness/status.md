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
- [x] Independently validate retained historical evidence; independent remote CI confirmation remains open.
- [x] Run fresh controller and production tests (rerun after each compiler increment).
- [x] Initial 20-subsystem audit; deeper coverage and remediation continue.
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

### P0-002 in progress: full-width seed integers
- Implemented immutable wide integer carrier (header 12) alongside existing odd immediates. Numeric operations, comparisons, integer text, native helpers and region evacuation now recognize boxes. Static large constants use read-only boxes; arithmetic boxes only results outside signed 63-bit range.
- Direct seed regression observed failure at integer text before fix, now passes constants/arithmetic/returned record and array values, wide shifts/masking and division overflow. Wide main exit status separately observed wrong result 80 before startup fix, then correct result.
- Rebuilt development compiler passed all 720 native differential cases, previously failing. Added direct seed standalone differential route; all 720 cases pass there too.
- Fresh review identified a stale integer_only exclusion in loop evacuation/liveness. Added a parameter-free 20-million-iteration wide arithmetic test under 128 MiB; reproduced OOM exit 126, removed stale exclusions, test now passes. Initial parameterized probe passed because PARAM already excludes integer_only; no false regression claim.
- Additional native-record suite fails at native_generic_pattern_ref_check.sh: unknown type_binding.constant_value option[expr] transfer type. Same failure reproduced with frozen original seed, establishing pre-existing fixture/dependency gap. No skip or assertion change; this remains to repair after current P0.
- README's seed-runtime-regression target is absent; no runtime suite PASS claimed for that attempted command.
- Full production suite rerun started after seed changes; pending. Fresh full bootstrap remains required before marking P0-002 complete.
- Alias test now invokes tracked canonical shell driver through sh, avoiding dependence on ignored bin/s which clean-room production intentionally does not build.

### Additional coverage and review follow-through
- Expanded differential operands at both signed 63-bit carrier transitions; 900 cases now pass directly through seed standalone and rebuilt development compiler.
- Direct seed memory/argument, dead-loop liveness/scratch growth, hexadecimal integer and record-copy rollback checks pass. Logs int64-argument-region.log, int64-loop-liveness.log, int64-hex-integers.log, int64-record-rollback.log.
- Compiler guide's first-program command compiled and executed with exit 25 for input 7 (tutorial/build.log).
- Repaired stale generic-pattern fixture by including actual option/prelude/AST record dependencies. Original seed reproduced its failure; real matcher assertions unchanged, focused check now passes.
- Declaration-kind fixture also failed with original seed. Added its actual AST dependencies and the declarations-only mono_index fixture required by the current real lookup implementation (it already used a declarations-only mono_context). Function bodies/assertions unchanged; focused check passes. Full native-record suite rerun pending.
- Signed literal regression now permanently reproduces all five valid-source failures; range-rejection and output-preservation checks already pass. No signed-literal compiler fix yet.
- Full production run after seed int64 changes exited 0 (int64-production.log), including all prior recipes and new seed/native differential and memory regressions. New native differential expanded to 900 cases also independently passed. Fresh staged acceptance still pending; P0-002 not yet closed.
- Native-record suite has another pre-existing failure: native_call_option_context_check.sh accepts incorrect option payload at call. Reproduced using original frozen seed; actual seed semantic correctness issue remains open, no test weakened.

### Signed literal increment: P1-004/P1-005
- Canonical integer lowering now accumulates negatively with checked signed limits, supporting signed switch patterns and the minimum int64 value. Parser preserves ordinary unary zero-minus ASTs and represents the minimum literal directly.
- Five original valid-source failures reproduced before fixing (signed-integer-red.log), then passed (signed-integer-green.log). Expanded boundary coverage adds positive maximum, minimum-plus-one precedence, leading-zero positive overflow and below-minimum switch rejection (signed-integer-expanded.log).
- Independent read-only review found no correctness defects; suggested boundary coverage was added. Existing canonical statement-boundary and switch AST checks passed, preserving established unary AST behavior.
- Rebuilt compiler from changed S sources; complete production target exited 0 (signed-production.log). Expanded regression independently passed after review. Fresh staged acceptance at the final source revision remains required.
- A fresh frozen full bootstrap at 8ca674d6f is running separately (int64-full-bootstrap/); it predates signed-literal changes and cannot certify them.

### Documentation and measurement increment
- Removed README commands for missing targets; checked every README make target against the current makefile and every linked doc path for existence. Corrected current binary provenance and clean-room versus development bootstrap instructions. Removed the missing target-info command from platforms.md.
- Added a canonical native benchmark harness retaining source/assembly/binaries, commands, hashes, source diff, compiler/tool versions, per-command elapsed/RSS and repeated correctness checks. Scalar sum and recursive Fibonacci completed warmup plus five runs for both S and C (benchmarks-signed-v3/results.json). Concurrent bootstrap load makes these preliminary harness measurements, not a release performance baseline.
- Initial benchmark attempt used historical parenthesized loop syntax; canonical parser rejected it. Switched workload to established canonical for syntax; failed attempt retained at benchmarks-signed/.
- Read-only connected GitHub queries for baseline 35fae2bf returned no commit statuses and no PR workflow runs. The workflow query explicitly covers PR events only; empty output does not verify or disprove historical push Actions acceptance. Independent CI confirmation remains open.

### Canonical type-tree fixture and broader seed coverage
- Broader native-record checks exposed another incomplete fixture closure: declaration_ref now embeds AST enum_variant[] and field[] types. The fixture omitted their actual declarations, causing unknown native array transfer type. Reproduced with current seed and original accepted seed emitter (type-tree-red.log, type-tree-baseline.log).
- Added actual prelude/option/AST dependencies, leaving production helper bodies and all assertions unchanged. Focused execution passes (type-tree-green.log).
- Complete selfhost-native-record-check now exits 0 with the strict enum candidate and repaired fixtures (enum-record-suite.log), including hosted/native record matrices and lexer stress. This broader target is additional to canonical production, which is still running for the enum increment.
