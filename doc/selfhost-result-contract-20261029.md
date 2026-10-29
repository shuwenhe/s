# Self-hosting: explicit backend result contracts (2026-10-29)

## Diagnosis and source correction

The preceding complete Stage1 first rejected `ok_write_ops` at
`core/backend.s:38`: its declared return was `(write_op[], backend_error)`, while
its body returned `result.ok(value)`. Contextual constructor inference reported
`unknown`, followed by e3008.

This was a source contract inconsistency. `doc/s` defines multi-return functions
with `return first, second`; `src/result/result.s` separately declares the tagged
`result[t,e]` enum with `ok(t)` and `err(e)`. Existing tuple semantic regressions
explicitly reject converting a result enum value to a tuple. The adjacent
`ok_function`/`fail_function` pair already uses explicit `result[...]` types, and
the backend's real `write_result_*`, `value_result_*`, `unit_result_*` and
`int_result_*` callers consume tagged results with those explicit types.

Eight historical helper declarations were inconsistent with these bodies and
callers: `ok_write_ops`, `fail_write_ops`, `ok_value`, `fail_value`, `ok_unit`,
`fail_unit`, `ok_int`, `fail_int`. Their return signatures now explicitly use
`result[...]`. Their bodies are unchanged. Genuine tuple-return functions,
including the Go assembly translator functions, remain unchanged. Neither
Semantic nor Parser was changed in this iteration, and tuple/result compatibility
was not relaxed.

## Tests

`canonical_backend_result_contract_check.sh` extracts the eight actual production
helper definitions and their dependent production types rather than recreating
look-alike implementations. A natively executed production semantic component
checks all eight plus eight explicitly typed result callers. It also accepts a
true tuple return and requires e3008 for six result/tuple or payload-type
mismatches. Invalid fixtures all have an entry function, preventing rejection
for an unrelated missing-main error.

The positive actual-helper contract first failed with e3008 on the original
source, then passed after the signature correction. A separate trusted-Seed
native component executes all eight actual constructors through eleven actual
production tag/payload consumers. It verifies array fields, value/int payloads,
unit success, and all four error messages, returning 42. This is a component
behavior test, not a claim that canonical native generic-result lowering or
complete self-hosting has been established.

The full production suite exited 0 with all 40 checks passing (39 existing plus
this new contract check), using the rebuilt native production compiler:
`make -o compiler selfhost-canonical-production-check`.

Initial test-fixture failures were corrected before that final successful run:
the Seed IR's 1024-byte operand limit requires chunking the long embedded source;
all main-package semantic fixtures need a main function; the runtime fixture now
uses actual production consumers and a local record identifier for its array
literal. No production parser, Seed, or semantic rule was changed for those tests.
Independent review found no correctness issue in the source signatures or final
regression coverage.

## Full-source progress

The rebuilt native production compiler parsed the frozen 268-file compiler
closure and cleared all eight corrected helpers. Its next rejection is
`e3020: equality compare requires same type` in
`build_object_interpreted_legacy` (`core/backend.s:217`), measured at 292.076 s,
peak RSS 1227620 KiB. A separate native semantic diagnostic component locates
the same failing function. Further focused diagnostics and complete Stage1
measurements follow below.

The trusted optimized Seed built complete native Stage1 from the frozen sources:

| Step | Time | Result |
| --- | ---: | --- |
| Seed to Stage1 IR | 162.930 s | PASS |
| Native Stage1 emission | 335.753 s | PASS |
| Total | 498.683 s | PASS, peak RSS 723412 KiB |

Evidence is retained in `.bootstrap/selfhost-result-contract/`, including the
frozen source manifest and SHA-256 values, full-source logs, and diagnostic
component outputs. Complete self-hosting remains unproven until Stage1
independently produces Stage2, Stage2 produces Stage3, and the resulting assembly
and executable bytes converge.

## Complete Stage1 verification and next FIRST RED

The complete-source Stage1 passed native verification and the statement-boundary,
if/never and string-ordering native regressions. It then compiled the same frozen
268-file source set toward Stage2, exited 1 (not a timeout), and reported e3020
after 291.294 s, peak RSS 1227812 KiB. No Stage2 artifact or completion marker was
produced; Stage3 and byte convergence remain unproven.

The full-unit diagnostic identifies `build_object_interpreted_legacy`. A focused
native semantic diagnostic, retaining the complete unit's declaration context
but checking only that function, records:

```text
comparison op=== left=unknown right=string
left name=ssa_text
comparison op=== left=unknown right=string
left name=debug_map
comparison op=!= left=unknown right=string
left member=message
```

The first two comparisons are `core/backend.s:246` and `:250`. The source calls
`dump_ssa_pipeline` and `dump_ssa_debug_map`, but the actual S definitions are
`dump_pipeline` and `dump_debug_map` in package `compile.internal.ssa_core`.
`build_ssa_pipeline_with_graph_hints_and_margin` similarly differs from the real
`build_pipeline_with_graph_hints_and_margin`. The trusted Seed has explicit
name mappings for these historical call spellings. This is a concrete next
investigation target; this correction does not add aliases to canonical lookup,
assume unknown expressions are strings, or relax equality checks. Other unknown
member/return expressions in the same function are also recorded in the focused
log and remain unresolved.

All 268 frozen source hashes match the final working compiler source. Parser and
Semantic are byte-identical to the preceding verified statement-boundary build.
The new Stage1 IR and ELF happen to be byte-identical to that build: this change
corrects source return annotations, and the trusted Seed lowers those old/new
spellings identically. The change in first rejection is observed when that
compiler checks the corrected S source, not a change to canonical type rules.

```text
Stage1 IR SHA-256:
bda366287f97b0b49d890dd4cc372bab39296de950c6a0b47a875ac3cfee50c2
Stage1 ELF SHA-256:
3cc68df109ec60a188a46c2d8d9131204013ee229ff6eeea5cf59ac7a7a9d41f
```

Final evidence: `stage1-build.log`, `stage1-check.log`, `stage1-measurements.json`,
`stage2-compile.log`, `stage2-measurements.json`, `source-hashes.json`,
`diagnostic/run.log` and `diagnostic-focused/run.log` under
`.bootstrap/selfhost-result-contract/`. Final full-suite output is
`/tmp/s-result-contract-production-final.log`. Initial fixture failures are
preserved separately; the final suite exited 0 with all 40 checks passing.
