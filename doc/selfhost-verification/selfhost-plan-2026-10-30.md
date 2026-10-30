# Complete native self-hosting

Goal: compile all 268 production modules with native stage1, rebuild with
stage2, compare stage2/stage3 assembly and executable bytes, and run the
independent execution/source-dependence checks with both compilers.

Continue in this checkout as requested, using the canonical parser, semantic
checker, specialization, MIR, SSA and native backend. The C seed is permitted
only for stage1. Never bypass validation or use prebuilt compiler payloads.

- [x] Inspect existing bootstrap scripts, artifacts, source closure and reports.
- [ ] Measure the full-source stage1 pipeline and reproduce its current failure.
- [ ] For each failure, add a focused reproducer, trace the cause, repair it,
      and run its regression plus relevant existing checks.
- [ ] Rebuild stage1 from final sources; run the canonical bootstrap end to end.
- [ ] Verify stage2/stage3 convergence and independent execution; install stage3.
- [ ] Replace unsupported status claims with measured evidence.

## Execution ledger

2026-10-30: Existing stage1 artifacts are native but previous reports do not
prove full self-hosting. The full-source probe reaches the canonical parser and
semantic phase. Measuring completion and resource usage before selecting fixes.
The user's continuous-execution instruction supplies the execution preference;
use the existing checkout and continue without design/approval interruptions.

All 38 canonical production scripts passed against bin/s_compiler. A 1000-caller
stress measurement isolated specialization peak growth to 2.8 GiB. Expanded
canonical_mono_memory_check.sh to 1000 callers / 512 MiB: RED (allocation failure).
Root cause: monomorphize_file writes through its source_file parameter, disabling
loop-region reclamation. Construct the output separately to preserve the input.

Specialization fix GREEN: rebuilt complete native stage1 compiles 1000 generic
callers within 512 MiB, links them and executes with result 42. Its specialization
function now has loop-region reclamation (six region-return sites versus one).

Receiver regression RED: generic/concrete same-named methods fail with
unknown callee main.get__mono_int. specialized_instance_name omitted the owner;
include the instantiated nominal owner before method specialization suffixes.
The existing canonical_generic_production_check also reproduces this failure
(native status 13), despite the smaller standard production suite passing.

Annotation investigation: nested argument allocations in ca_infer/ca_stmt force
snapshots of preceding immutable symbol tables. Hoist empty borrow/diagnostic
allocations before passing arguments, preserving evaluation and type checking.

Receiver follow-up: owner-qualified calls then correctly failed because no
specialized declaration existed. collect_method_call_instance_ctx compared
qualified inferred owners against unqualified source spellings. Match Semantic's
resolved nominal owner against package-qualified declaration metadata and carry
the exact declaration index; qualify cache/work identities to avoid collisions.

Cross-package receiver test exposed annotation's unqualified receiver binding;
use canonical_type_in_package exactly as check_receiver_method does.

Optimized trusted seed built with GCC -O2. On a record/call fixture it emits
byte-identical seed IR and AMD64 assembly to the unoptimized seed. Full 268-file
seed IR emission takes about 158 seconds; assembly emission takes about five
seconds. Make the optimized build the default, keeping SEED_CFLAGS overridable.

Receiver fixes GREEN: complete native stage1 executes generic/concrete methods
with the same name, plus same-named generic receiver declarations in two packages.
It also passes independent source-dependence and static native execution checks.
Installed this verified stage1 as bin/s_compiler for the broader regression run;
this is not installation of a self-hosted stage3. Original production compiler
preserved at .bootstrap/selfhost-20261030/production-before-fixes.

All 40 production regression scripts passed with nominal-fix stage1, including
the expanded memory test, generic source-to-MIR and executable receiver tests.

Entry ordering RED: helper.s before main.s failed with entry function not found:
helper.main. lower_source_program must derive its entry package from the unique
main declaration, not the first dependency package; multiple mains are rejected.

Further annotation optimization: ca_expr mutated its large context only to reset
discard_result. Pass this scalar separately so recursive expressions can share
read-only lookup metadata. Extract small scope fields into independent locals;
constructing semantic_scope otherwise marks the whole context as escaping.

Entry fix GREEN: execution succeeds with entry-first and dependency-first file
orders; an ambiguous entry rejects without replacing the existing artifact.
The latest context-fix stage1 also passes receiver and 1000-caller memory checks.
Its expression/inference call sites now pass the lookup context without snapshots,
confirmed in the emitted assembly. Running all 41 production checks on it.
Additional payload-enum and borrowed-record source-to-native probes both pass.

All 41 production checks GREEN with context-fix stage1; complete log:
.bootstrap/selfhost-20261030/context-production-checks.log. Full-source native
compilation is still in progress; stage2/stage3 convergence remains unproven.

Executable reachability RED: a checked but unused function's literal payload
survives into a native executable. This also retains obsolete forwarding-launcher
strings from the complete compiler source. Prune functions only after full SSA
and AMD64 validation, root the entry and all global initializers, and retain the
transitive verified call-edge closure. Object emission remains unchanged.

The initial declaration-heavy scaling fixture passed; the refined fixture with
1000 callers, twenty statements each, and a late generic declaration timed out
at 120 seconds specifically after annotation (2 GiB limit). Inspection found
collect_call_instance_ctx unconditionally scans the entire AST before using its
existing declaration index. Use the exact index first; process work items by
their known declaration indices instead of scanning before overwriting results.

Type requests RED: te_add_requests retained duplicate normalized requests from
one package. te_enqueue now stores one parsed type/package key; requests from
different packages stay distinct. Pointer/array/tuple expansion uses the same
queue. The generic type-elaboration fixture is GREEN, including recursive types
and cross-package request identity. Its semantic fixture was updated to retain
the current const_binding/function_binding definitions and exact path helpers.

Indexed lookup alone did not meet the larger traversal's 120-second bound.
Phase tracing confirms repeated context copying during initial collection.
Separate immutable mono_index metadata from mutable mono_context for the seven
recursive collectors; retain compatibility wrappers and restore declaration
metadata once for the final identity-verification gate.

Continuation: reproduced `unsupported record field type: Graph` with an imported
record nested in another record. Ruling: preserve Semantic's nominal identities
in canonical annotation (fields, signatures, constructors), rather than accepting
unqualified names in the MIR validator. This keeps validation independent and
avoids selecting a same-named layout from another package. Regression:
`canonical_nominal_layout_check.sh` (RED with current bin/s_compiler).
Nominal layout regression GREEN with rebuilt native stage1. Receiver regression
then exposed type elaboration stripping the package from already-qualified
same-package type requests; retain that package when building aliases.
Nested array `.push` regression RED: qualified call requires package identity.
Lower checked array methods using the existing named-place reconstruction path.
Array backend investigation found two additional RED executions in the existing
uncommitted capacity optimization: appending to a default array segfaults (139),
and appending to an alias changes the saved array length (43 instead of 42).
The changed layout also disagrees with run_argv's element offsets. Ruling:
restore the established persistent array representation and allocator before
attempting further optimization; bootstrap correctness takes priority.
Receiver regression GREEN after package-preserving alias fix. An existing
`program_array_method` implementation already handles the desired named-place
updates but had no call site; use it instead of duplicating its implementation.
The traced 1000-caller scaling regression now completes function specialization,
but times out during type elaboration. Seed emission shows that assigning
`append(output.items, value)` snapshots the entire accumulated AST vector at
every iteration. Use the existing `.push` operation: its seed lowering snapshots
only the new item and shallow-copies the descriptor, preserving value isolation
without repeatedly deep-copying every previously collected declaration.
Type elaboration's focused native tests GREEN, including recursive records and
cross-package generic arguments. Apply the same output-list update to mono's
extra/stripped declaration vectors. Imported typed array constructor regression
RED (`member target is not a record: Graph`): array annotation must retain the
resolved array type, not the original unqualified element spelling.
The expanded production sweep also found a pre-existing forward-global inference
failure in canonical_environment_production_check.sh, reproduced unchanged with
original bin/s_compiler; it is separate from the continuation's regressions.
Imported array regression GREEN with latest native stage1. Scaling now reaches
native assembly within the existing bound, but still times out there.
External-declaration reproducer RED: unused tuple-returning stdlib extern rejected
by function_mir_input_error. Model declarations as empty SSA functions with -1
entry/exit sentinels; validate their signatures and all ordinary bodies, prune
only after complete SSA/AMD64 validation, and reject any retained declaration at
emission. Raw native SSA tests GREEN for empty signatures, reference escapes,
invalid sentinel state, declarations with bodies and definitions without bodies.
The legacy interpreter function-SSA script also encounters missing-field errors
on existing fixtures (successors); native contract tests are used for this gate.
Scaling GREEN with output-push stage1: 1000 callers / 4000 fields within the
original 2 GiB / 120-second gate. Full generic source-to-MIR regression GREEN.
Code review found no important issue in nominal/array/type/specialization fixes
or external SSA declaration handling. Minor deferred: raw SSA permits a
bodyless global initializer, while MIR rejects it; source compilation remains
protected and executable emission rejects retained externals. No acceptance
criterion depends on that raw-only permissiveness.
Fresh sentinel-stage1 acceptance regression sweep GREEN: all 46 scripts in the
selfhost-canonical-production-check recipe pass; complete log:
`.bootstrap/accept-production-checks.log`. Compiler source hashes remain equal
to `.bootstrap/selfhost-accept/source-sha256`; the complete native stage2 run
has passed parsing and semantic checking and is annotating calls.
Concurrent workspace update detected: semantic.s specialized_instance_name now
qualifies non-receiver callees by declaration package. Preserved the change.
Focused RED reproducer confirms the old stage1 rejects an unqualified imported
generic call (`unknown callee: main.identity__mono_int`), while its explicitly
qualified equivalent executes with 42. Added package-specialization regression.
This invalidates the running acceptance source snapshot; retain that run as a
diagnostic probe and repeat final acceptance from the integrated stable sources.
Integrated stage1 rebuilt from all 268 modules with the concurrent package fix;
artifacts in `.bootstrap/selfhost-integrated`. The earlier full-source probe is
still elaborating types; no diagnostic or stage2 artifact yet.
Full probe reached MIR lowering and rejected the known ordinary imported callee:
`compile.internal.abi.to_string` in `reg_string`. Its total elapsed time was
28:38, peak RSS 2.52 GiB. Both ordinary and generic imported calls execute with
the integrated package fix.
Qualification scaling RED: 2000 nominal declarations / 500 irrelevant imports
causes a primitive qualification request to time out at 30 seconds. Root cause:
te_qualify_type rebuilt a map of every visible nominal name, resolving unrelated
imports per declaration. Resolve only actual type components recursively, and
skip primitive declaration lookup. Focused type-elaboration/qualification suite
GREEN after repair, including nested arrays/tuples/generic arguments. Add optional
collection/request/rewrite trace points to distinguish any remaining slow phase.
Updated source-stable stage1 GREEN on all 47 canonical production scripts,
including ordinary/generic imported calls; log:
`.bootstrap/qualified-production-checks.log`. Full-source run is in annotation;
its compiler source checksums still match the start snapshot.
Qualified probe completed all frontend phases and reached MIR lowering in 18:02
(previous 28:38), peak RSS 2.52 GiB. Next concrete failure:
`index requires an array in compile.internal.abi.starts_with`. A concurrent
program_lower.s edit already lowers string indexing to existing string_byte_at;
preserved it and added a focused RED execution fixture covering single index
evaluation, default/bounds behavior and UTF-8 byte distinctions. String indexing
has semantic type u8, so tests compare indexed byte values directly. User has
asked other compiler edits to pause for the final source-stable run.
String-index stage1 GREEN on focused byte indexing (bounds/defaults/UTF-8 and
single evaluation), package qualification and external declaration tests. All
48 canonical production scripts GREEN; complete log:
`.bootstrap/string-index-production-checks.log`. Current source-stable bootstrap:
`.bootstrap/selfhost-string-index.log`.
String-index probe passes the previous ABI failure; next MIR blocker is a
discarded switch in ast.dump_function whose arms return string[] and unit.
Semantic correctly types the discarded expression as unit, but lowering merges
unused arm values anyway. Focused discarded-switch execution regression RED.
Preserve all arm effects and binding phis; emit unit instead of a result phi only
when the checked switch annotation is unit. Value-producing mismatches still
reject in Semantic. Rebuild and repeat full-source bootstrap after verification.
The same checked-unit result bug also reproduces in `if true { tick() }`: RED
`phi input type mismatch`. Apply the same rule after merging binding updates in
program_lower_if. Keep both-terminated handling and value-producing branch phis
unchanged. Extended the focused test with taken/untaken effectful unit ifs.
Checked-unit switch and if regressions GREEN with rebuilt unit-control stage1.
Review found no correctness issue in never/live exit or binding-merge handling.
A further concurrent diagnostic edit in program_payload.s invalidated this
snapshot after stage1 built. To prevent repeated invalidation, continue the
three-stage bootstrap in `.bootstrap/frozen-selfhost-source`, a copy of src,
misc, test, makefile and the trusted seed. Root remains intact. Compare verified
frozen sources against the checkout before final installation.
Frozen stage1 GREEN on all 49 canonical production scripts (including discarded
switch/unit-if regression); log:
`.bootstrap/frozen-selfhost-source/.bootstrap/production-checks.log`.
The isolated full-source bootstrap has passed Semantic and is annotating calls.
