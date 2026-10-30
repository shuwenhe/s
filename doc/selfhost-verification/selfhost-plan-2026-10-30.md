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
