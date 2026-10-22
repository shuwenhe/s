# Native Record ABI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Review status:** DESIGN REVIEW — CONDITIONALLY APPROVED direction only; revised full text awaits formal APPROVED. Native execution is proposed, not authorized. SELFHOST = NOT PROVEN.

**Goal:** Make the complete-source native stage1 preserve plain record values across construction, copies, nested field accesses, arguments, and returns, then compile a small S program without crashing.

**Architecture:** Preserve the seed IR's logical operations and tagged-word calling convention. Lower plain records to tag-8 heap objects with named field tables, replace flattened record slots with runtime accesses, and copy value records at binding/call/return boundaries. Keep enum/result compatibility explicit and use hosted execution as a differential oracle.

**Tech Stack:** C11 seed compiler, GNU amd64 assembly, Linux syscalls, Bash regression runners, GNU as/ld.

**Spec:** `docs/superpowers/specs/2026-10-22-native-record-abi-design.md`

## Global Constraints

- Record header: 32 bytes; tag 8 at offset 0, qualified type-identity pointer at offset 8, field count at offset 16, field-table pointer at offset 24.
- Field entries: 16 bytes, full field-name pointer then tagged value. Full-name comparison determines identity.
- Preserve `SSEED-TARGET-V1`, odd tagged integers, string tag 2, array tag 4, rope tag 6, and existing SysV register/stack argument ordering.
- Only statically classified `copy_value` records/arrays are recursively copied. Proven `shared_borrow`/`mutable_borrow` handles preserve referent identity and qualifier/lifetime rules. Reject `unsupported_owner`, unknown raw-pointer ownership, and explicit moves; copying is not S ownership.
- Successful copyable backing is process-arena storage with no per-object destructors. Failed top-level copies rewind only their unpublished allocation transaction; fail-stop paths never publish partial objects or invoke the target callee.
- Caller snapshots each argument immediately after its left-to-right evaluation. Callee adopts snapshots without entry copying. Callee snapshots record returns into `%rax`; caller adopts without a second copy. Helper-only status: `%rdx` 0 success, 1 allocation, 2 invalid operation; generated failure exits 70/71.
- Initialize declared fields to their language-defined defaults before applying explicit initializers. Package-qualified types remain distinct.
- Invalid record operations fail with a diagnostic and nonzero status, never a guessed field offset or an uninitialized local slot.
- Compile the full production closure. No C compiler/interpreter fallback, source exclusion, or fixture-specific output.
- Statically reject unsupported ownership/move and illegal/unknown borrow contracts for the entire compilation unit before IR lowering, output replacement, native tool invocation, or program execution. Independently validate external IR metadata before assembly emission.
- Gate H uses a frozen source/option/environment/tool/protocol manifest and raw byte comparisons only. Time/date, random IDs, PIDs, and temporary/output/source absolute paths may not leak into serialized artifacts; no post-production normalization.
- Existing uncommitted protocol/runtime work remains in place. Keep commits limited to verified changes from this plan; do not sweep unrelated files into commits.

## Review Focus

1. Nested copy then mutate must preserve the source record, including array elements.
2. More than six arguments must preserve values and callee-saved registers across helper calls.
3. Reordered initializers, omitted defaults, and equally named types in different packages must retain field/type identity.
4. Borrowed receivers preserve alias identity/exclusivity; owner-bearing fields and explicit moves are rejected without resource acquisition or release.
5. Copy failure, invalid fields, and malformed ownership metadata must not publish values or enter the target callee; full selfhost requires actual stage2/stage3 execution and raw byte convergence.

---

### Task 1: Record behavior harness and schema metadata

**Files:** Create `test/native-bootstrap-diagnostic/native_records_check.sh` and fixtures under `test/native-bootstrap-diagnostic/native-records/`; modify `src/cmd/compile/seed/intermediate/ir.c`, `src/cmd/compile/seed/code/standalone_amd64_backend.c`.

**Interfaces:** Add `standalone_record_schema` and `standalone_record_field` native module metadata. Encode schema facts using existing no-op records: `NOP|record-field:<qualified-type>|<field-name>|<field-type>`. Hosted execution ignores these facts; the standalone analyzer validates and collects them. Field types retain borrow/owner qualifiers and map to immutable transfer descriptors. Retain function parameter/return and binding classifications with `NOP|param-transfer:<qualified-function>|<zero-based-index>|<kind>:<qualified-type>`, `NOP|return-transfer:<qualified-function>|_|<kind>:<qualified-type>`, and `NOP|binding-transfer:<qualified-function>|<binding>|<kind>:<qualified-type>` respectively; native module metadata decodes these records before code emission. Reject erased or contradictory transfer information. Preserve existing constructor `MOV` patterns and the IR header.

**Preflight interfaces:** `record_validate_transfer_contracts(ast_node *unit, record_contracts *out, compile_error *err) -> bool` runs after name/type resolution and before record IR lowering or output-file replacement. `standalone_validate_record_contracts(standalone_module *module, compile_error *err) -> bool` runs after complete schema/transfer metadata loading and before assembly output/tool execution. Both fail closed when ownership or borrow facts are unsupported/unknown; diagnostics identify source spans, or the external IR file and record index when spans are unavailable; no runtime stub substitutes for rejection.

- [ ] Write `nested_call.s`: construct a record containing a string and nested record; pass and return it; assert literal field values and exit 42. The runner builds hosted and standalone executables from the same generated IR, checks literal expected statuses/output, enforces timeouts, and retains failure evidence.
- [ ] Run `make seed-compiler-bin && bash test/native-bootstrap-diagnostic/native_records_check.sh nested_call`; verify hosted returns 42 and native exposes the record failure.
- [ ] Collect declaration schemas from the seed's parsed record declarations, preserving package/import identity. Emit the no-op field metadata and collect it in the standalone module before analyzing function slots. Reject contradictory field definitions and unknown declared field types.
- [ ] Add hosted behavior fixtures for initializer reordering, omitted int/bool/string/array/nested-record defaults, and same-name records in two packages. Assert exact expected values, not metadata text. Confirm the metadata does not change hosted behavior.
- [ ] Add classification rejection cases for a resource-bearing nested record, owning-pointer array element, explicit move, and raw pointer with unknown ownership. Verify a specific unsupported-transfer diagnostic before object construction or destructor calls; do not use hosted deep-copy behavior to justify resource duplication.
- [ ] Write `reject_before_effects` fixtures for owner copy, explicit move, invalid shared-borrow mutation, mutable-borrow duplication/escape, and unknown ownership, including operations after an effectful expression and in an unreachable branch. Compilation must return nonzero with the matching diagnostic. Preserve a sentinel output byte-for-byte, create no runnable artifact/resource/destructor marker, and record zero calls to fail-if-invoked assembler/linker wrappers. Repeat malformed/forged descriptor cases through the native IR input boundary.
- [ ] Implement both preflight interfaces and wire them ahead of lowering/output replacement and native assembly/tool emission respectively. Inspect the whole unit rather than only reachable runtime branches; keep defensive runtime status-2 checks for genuinely dynamic invalid values separate.
- [ ] Commit the harness and schema changes after seed compile/unit-boundary/package-signature regressions pass.

### Task 2: Tagged record construction and field places

**Files:** Modify `src/runtime/selfhost_linux_amd64.S`, `src/cmd/compile/seed/code/standalone_amd64_backend.c`; extend the Task 1 fixtures.

**Interfaces:** SysV tagged-word runtime helpers:

- `s_record_new(schema_pointer) -> (%rax record, %rdx status)`: allocate tag-8 object and initialized field table.
- `s_record_get(record, field_name) -> (%rax value, %rdx status)`: return the stored value for expression/place traversal.
- `s_record_set(record, field_name, prepared_value) -> (%rax record, %rdx status)`: validate an existing field, then install the already-prepared value. On error leave the destination unchanged.
- `s_record_type(record) -> (%rax qualified_type_string, %rdx status)`.
- `s_record_error(status)`: diagnose allocation or invalid-operation failure and exit 70 or 71. Status values are untagged: 0 success, 1 allocation failure, 2 invalid operation.

The immutable schema descriptor provides type identity, field count, names, default kinds, and transfer descriptors. Field-table storage is heap-owned; no runtime record refers to stack-local slots.

- [ ] Add failing fixtures for two distinct integer fields, a string field, nested field read/write, reordered initialization, defaults, invalid field access, and repeated loop constructors with independent results.
- [ ] Implement runtime helpers with allocation checks, aligned tagged values, full-name matching, and callee-saved register preservation. Recursive defaults use the declared field schema; invalid by-value recursive schemas are rejected during analysis.
- [ ] Recognize constructor initialization in `emit_function`. Allocate a record at constructor start instead of storing the textual temporary alias. Initialize named fields through the helpers.
- [ ] Replace plain-record dotted reads/stores in `emit_load`/`emit_store` with root-value traversal. Change `emit_store` to accept the module metadata required for field names. Keep ordinary local slots and explicit enum/result compatibility paths separate; remove offset-8 guessing for plain record fields.
- [ ] Run the field/default/invalid-input fixtures and source-reader/reachability checks. Record reads and writes must pass independently before enabling copy semantics.
- [ ] Commit runtime construction and place lowering.

### Task 3: Value copies, parameters, and returns

**Files:** Modify the same backend/runtime files; extend `native-records/` fixtures and runner.

**Interfaces:** `s_value_copy(value, transfer_descriptor, copy_context) -> (%rax value, %rdx status)` handles classified scalars, strings, tag-8 records, tag-4 arrays, and proven borrows. `s_record_copy(record, transfer_descriptor, copy_context)` has the same two-register result and recursively clones copyable fields. A context stores the initialized arena checkpoint for one unpublished copy; nested helpers share it. `s_copy_begin(context) -> %rdx status` initializes the arena if needed and captures the checkpoint only after successful initialization; `s_copy_abort(context)` restores the cursor without shrinking reserved capacity; `s_copy_commit(context)` makes the result eligible for publication. No copying helper invokes user code or destructors. By-value recursive schemas, concurrent/reentrant allocation, and unknown ownership are rejected.

**Caller/callee ABI table (normative, matching the spec):**

| Transfer | Copy owner | Caller action | Callee action | ABI |
| --- | --- | --- | --- | --- |
| By-value argument | Caller, exactly once per argument boundary | Evaluate argument, copy immediately, check status, stage copied pointer | Bind the snapshot without copying | One tagged word; first six arguments in `%rdi/%rsi/%rdx/%rcx/%r8/%r9`, then 8-byte stack slots |
| Proven borrow | No referent copy | Validate qualifier/lifetime, stage identical handle | Preserve alias and shared/exclusive restrictions | Same one-word placement |
| Record return | Callee | Adopt returned snapshot without a second copy | Copy expression, check status, return | `%rax`; no hidden sret |
| Helper result/failure | Helper transaction | Commit only on status 0; else diagnose and exit before target call | Rewind unpublished partial copy on error | `%rax` value; helper-only `%rdx` status 0/1/2 |

Ordinary S calls do not return helper status in `%rdx`. Caller aligns `%rsp` to 16 before `call`; callee entry has `%rsp mod 16 = 8`, with argument 7 at `16(%rbp)` after the standard frame prologue. Preserve `%rbx/%rbp/%r12–%r15`. Stage all arguments in stable storage before final ABI-register loading. Argument evaluation and snapshotting alternate left to right; stop before later arguments on failure. Earlier expression side effects remain. Earlier completed snapshots are arena-owned until process exit; only the currently failing copy is rewound.

- [ ] Add failing cases: copy then mutate; nested copy then mutate; parameter mutation does not affect caller; returned record survives later calls; record passed as seventh argument; mixed scalar/record arguments; array of records with one element updated; repeated calls returning independent objects.
- [ ] Implement generic and record copy helpers for classified copyable values and proven borrows. No implicit moves or resource destructors. Ordinary value assignment snapshots; explicit moves and resource-bearing transfers fail compilation.
- [ ] Add a test-only allocator/link harness that fails every allocation point in a nested record/array copy, including arena initialization. Assert status 1, active-checkpoint restoration, unchanged source and preexisting destination, and no partial publication. Verify invalid descriptors give status 2 and never call user destructors. No production fault-injection switch is added.
- [ ] Apply binding/field-store copies before destination publication. At calls, caller snapshots each `ARG` immediately after its expression (not deferred until `CALL`), left to right into staging storage, then loads ABI registers/stack once all succeed; callee binds the supplied snapshot. At returns, callee prepares the snapshot in `%rax`, and caller adopts it without cloning again. Preserve stack alignment and callee-saved registers.
- [ ] Add a boundary harness with independently compiled caller and callee, register sentinels, seventh/mixed arguments, and helper-call counters. Assert one snapshot per argument/return boundary, no entry/adoption duplicate, left-to-right expression/snapshot order, no later expression evaluation after failure, exit 70/71, and zero target-callee entries after a failed argument copy.
- [ ] Add shared-borrow identity and rejected-write fixtures, mutable-reborrow owner mutation with caller access suspended, and rejected escaping/unknown-lifetime cases. Retain alias identity inside copied containers. Keep enum/result fixtures passing without reinterpreting their legacy tag layout as tag-8 records.
- [ ] Run all literal-oracle fixtures under hosted and native execution. Require identical statuses/output, and no timeout, SIGSEGV, or unknown-field fallback.
- [ ] Commit value-transfer semantics.

### Task 4: Full-source stage1 execution and regression evidence

**Files:** Create `test/native-bootstrap-diagnostic/native_stage1_record_check.sh`; modify `makefile`, `src/cmd/dist/README.md`, and this plan's progress checkboxes. Keep `native_stage1_check.sh` as the full compile-and-emit frontier.

**Interfaces:** New `make selfhost-native-record-check` reports **Gate R** (record fixture matrix + complete-source stage1 small-program assembly). Existing `make selfhost-native-stage1-check` remains a native small-program compile/emit frontier, not full selfhost evidence. `make native-bootstrap-imports` is the complete-source **Gate H** entrypoint.

**Independent acceptance contracts:**

| Gate | Required execution | Equality/output test | Permitted conclusion |
| --- | --- | --- | --- |
| R: record milestone | Full-closure native stage1 actually compiles small original/changed programs | Versioned `.sasm`, changed source changes output; independently checked runtime results 25/30 | Record milestone only; stage2 is not established |
| H: complete selfhost | C seed emits stage1; stage1 compiles/emits full-source stage2; stage2 runs and compiles/emits full-source stage3; stage3 runs; both later stages compile/emit/run small source-dependent fixtures | Raw `cmp -s` of `stage2.sasm` vs `stage3.sasm` **and** `stage2` vs `stage3`, with no normalization | Full native selfhost only when every transition, verifier, execution, and comparison passes |

Gate H uses a frozen complete production closure, fixed Linux/amd64 target, identical codegen options/relevant environment, and fixed assembler/linker versions. Output paths must not affect bytes. Record source/producer/artifact SHA-256 and tool identities for provenance, retain failed logs, and remove stale completion markers before starting. A normalized-equivalence check cannot satisfy Gate H.

**Reproducibility interface:** The bootstrap test wrapper creates `build-envelope.json` before stage1. It records ordered root-relative source paths and SHA-256 values, target, all compile flags, protocol versions, codegen-relevant environment allowlist, and resolved assembler/linker paths/versions/hashes. Pin `LC_ALL=C`, `LANG=C`, `TZ=UTC`, `SOURCE_DATE_EPOCH=0`, `umask 022`, recorded `PATH`, and selected tool paths; remove unrecorded overrides and disable debug metadata for this gate. Validate the manifest before/after every stage and write a mismatch reason before returning nonzero. Keep paths/provenance in logs, never in generated artifacts. This is a planned test/driver interface, not an existing implemented feature.

- [ ] Add a failing complete-source record check: build the full production closure, emit standalone stage1, run the existing verifier, then use stage1 to compile `func main(int value) int { return value * 3 + 4 }` to `.sasm`. Require the exact version header and executable startup assembly.
- [ ] Compile a second fixture with `+ 9` and require a different artifact. Use the existing hosted S artifact emitter plus GNU tools only as an independent checker of those assembly artifacts; assert runtime statuses 25 and 30 for input 7. Label this checker's authority separately from the native producer.
- [ ] Fix record-specific failures exposed by the complete-source run using a minimal fixture first. Do not patch the compiler's particular `state.lex.error` value or remove closure files.
- [ ] Add reproducibility fixtures: build with the same frozen envelope in two different output parents; require raw equality for each equivalent `.sasm` and ELF artifact. Repeat under different ambient locale/timezone settings while the wrapper enforces the pinned allowlist. Mutating a closure source, flag, tool hash, or protocol field must fail manifest validation before the next stage, not quietly update the manifest.
- [ ] Make schema traversal/symbol/label emission deterministic. Reject timestamp, random/PID-derived symbol IDs, and temporary/output/source-path leakage by cross-build byte comparison. Keep debug metadata disabled and preserve all produced bytes for inspection; do not run strip or a normalization filter before `cmp -s`.
- [ ] Add independent convergence-negative cases that vary only timestamp-like payload bytes, random IDs, or temporary paths, separately for assembly and binary outputs. Every mismatch must fail with `.complete` absent; report both hashes/diff location as evidence rather than repairing either artifact. Assert each actual stage CLI and changed-source smoke program was executed, not merely inspected.
- [ ] Run `make selfhost-native-record-check`, `make selfhost-protocol-check`, `bash test/native-frontend/check.sh`, `bash test/native-codegen/check.sh`, and `bash test/native-build/check.sh`.
- [ ] Run `make selfhost-native-stage1-check`, `make native-bootstrap-imports`, and `make pipeline`; report Gate R, Gate H, native service/frontend failures, and Stage 15 Layout separately. Until later stages exist, Gate H is failed/not reached, never inferred from Gate R.
- [ ] Add bootstrap-driver boundary fixtures for stage2/stage3 execution failure, later-stage verifier failure, assembly-only mismatch, and binary-only mismatch. Require each to fail without `.complete`. Add actual stage3 compiler execution and changed-source smoke execution to the Gate H driver when that path is runnable; retain raw byte comparisons. These checks implement the existing final selfhost contract without requiring unrelated frontend/service implementation inside the record milestone.
- [ ] Obtain a fresh review, fix important findings, update status documentation, and commit the verified record work without including unrelated prior changes.

## Execution handoff

Recommended method: native execution in the current session. The backend/runtime interfaces are tightly coupled, and the repository already has ongoing uncommitted bootstrap work. Implement tasks sequentially with their red/green checks, then request one independent final review. The review remains DESIGN REVIEW / CONDITIONALLY APPROVED direction only until the user explicitly marks the revised full documents APPROVED. Review and confirm the amended spec/plan before product-code changes; no execution approval is inferred from the stated preference for Native execution.
