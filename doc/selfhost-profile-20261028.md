# Native selfhost profile (2026-10-28)

Full selfhosting is not yet proven. Keep the Stage2/Stage3 convergence gate.

最新 continue 全链路验证及后续 FIRST RED 见 [selfhost-continue-20261028.md](selfhost-continue-20261028.md)。


## Reproduction and evidence

The preserved working Stage1 and SHA-256 are in
`.bootstrap/stage2-profile/stage1-baseline{,.sha256}`. The actual 268-file
Stage1 -> Stage2 invocation was profiled with a separately linked diagnostic
runtime: SIGALRM samples the PC/frame chain every 50 ms, and counters record
allocator requests, recursive copy visits, snapshots and region returns.
`ptrace` is unavailable in this environment. Production runtime semantics
were not changed by the profiler.

The parser ran **once**, accepting all **268 package declarations**, with
**304915 token advances** (including lookahead) and **2364 function parses**.
There were 4294769 record-constructor calls, including parser-state records;
this is not a count of distinct retained AST nodes. Repeated module parsing
is not the measured cause.

On this native path, string `+` uses `s_value_add` rope nodes (32 bytes plus
shared children), rather than copying the accumulated source bytes on each
concatenation. The input rope makes repeated random byte access expensive,
but the measured multi-GiB retention occurs after parsing in semantic value
snapshots. Moving the same concatenation loop behind a vector does not by
itself establish a fix for that retention.

At 60 seconds the original profile counted 1100002475 allocator calls,
62708273575 requested bytes, 1591516415 recursive copy visits and 74762206
snapshot calls. Requested bytes include reclaimed temporary allocations;
copy visits include scalar leaves. Neither metric means retained heap size.

At 180 seconds, peak sampled RSS was 6742 MiB. Major stacks were:

```
validate_function_set -> add_error -> locate_anchor / resolve_recovery_anchor
  -> s_string_byte_raw
check_item -> check_function -> infer_block_expr -> infer_expr
  -> s_value_snapshot -> s_value_copy_impl -> s_alloc
canonical_augment_function_bindings -> canonical_enum_type / canonical_enum_index
  -> s_value_snapshot
```

Per-callsite allocation counters identify incoming semantic context copies.
For example, `infer_expr+0x290f` and `+0x2a7d` in the diagnostic binary each
copied the `declarations` argument 295 times, requesting 232360880 bytes at
each callsite. Its `functions` and `traits` arguments were copied separately.
The offsets refer to the saved diagnostic ELF, not a source line or future build.

## Changes and semantic boundaries

Cross-package function names must not be diagnosed as duplicates. The actual
canonical semantic regression rejected two packages each defining `read`
with `e3010`; it now accepts them while rejecting same-package duplicates.

Previously, any global effect disabled return/loop temporary reclamation.
Appending a global diagnostic consequently retained private argument
snapshots across the checker. The seed backend now promotes explicit global
replacement roots with return values using the existing deterministic region
mechanism. Old-global in-place mutation, borrowed owners and unproved effects
remain ineligible. Indexing aliases must be followed through `READ` and
runtime `__index_get`: independent review caught this necessary exclusion for
nested global arrays, and its failing native example is now a regression.

Contiguous ARG snapshots can be consumed together at a proved callee boundary.
Intervening argument computations and pending outer calls keep their original
evaluation-time snapshots. Private mutation and nested-call ordering are
tested under 64 MiB.

A subsequent, more conservative optimization proves read-only parameters
only for callees without global/borrow effects. It follows indexing aliases
and rejects mutation/escape uses. Only a contiguous ARG suffix can share a
read-only input. MOV and RET still create independent owned snapshots. The
2000-call native counter test failed with 2004 aggregate snapshots before
this optimization and passes with 4 afterward. Independent review exercised
mixed readonly/mutating parameters, nested mutating callees and indexed
record mutation.

No ownership/schema validation was disabled. No GC, interpreter, C emission
fallback, source omission or precomputed compiler output was added.

## Measured results so far

| Real Stage2 run | Limit/result | Sampled peak RSS |
|---|---|---:|
| Original Stage1 | 300 s timeout | 8456 MiB |
| Region/global-root and ARG cleanup | 300.084 s timeout | 1022.7 MiB |
| Diagnostic flat-input experiment | 300.052 s timeout | 1025.2 MiB |
| Pure readonly-parameter proof | 300.042 s timeout | 861.8 MiB |
| Frozen full source + first-invalid-item compilation | e3011 rejection in 39.578 s | 1001.7 MiB |

The region run parsed in 24.526 seconds. RSS reduction is approximately 88%;
it does not establish successful Stage2 compilation. The flat-input experiment
shifted samples away from rope byte traversal but still timed out; its binary
is diagnostic-only and that input transformation was not added to production.

The bounded native multi-package regression now compiles 9/17/33 modules in
approximately 0.022/0.053/0.176 seconds, with 3.4/5.3/11.7 MiB sampled peak
RSS. It also executes 42 and rejects a same-package duplicate without
replacing the existing artifact.

The compiler-only rejection entry now stops after the first invalid item;
the complete diagnostic API still checks all items. Valid inputs traverse
every item and the canonical equality gate. Positive/negative native tests
verify both APIs, including complete-vs-first-error diagnostics.

## Correctness frontier after the performance repair

Matching same-package, same-library external contracts are merged by both
semantic checking and MIR construction. Conflicting contracts, different
libraries and ordinary duplicate bodies remain rejected. The native external
contract end-to-end test passes and preserves existing artifacts on rejection.

Declaration identity now follows lexical package and generic scopes through
function signatures, expression inference, record fields and AST annotation.
Field types are qualified in declaration scope before generic substitution.
Native positive and negative tests cover same-named records/enums, generic
parameters shadowing nominal names, record construction and tuple members.
Ambiguous unqualified records/enums must remain errors; selecting an arbitrary
same-named declaration is not a valid fix.

The subsequent diagnostic component frontiers were:

- `compute_padding`: typed-array `set` was absent from canonical method checks.
  `set`, `push` and `len` now check arity, index and element types.
- `append_param_offsets`: canonical parser split Seed's `var name = value`
  declaration into expressions. AST retention and semantic regressions pass.
  Local duplicate checks now track the block boundary rather than including
  outer parameters; same-block duplicate declarations remain rejected.
- `dump_const`: a local parameter `item` shadowed the AST enum `item`, but
  `item.value` was interpreted as a constructor. Local values now take
  precedence, including during AST annotation.
- `dump_function`: discarded switch statements incorrectly required matching
  arm result types. Discard context is local to the statement's root expression;
  value-producing switches still reject incompatible result types.
- `dump_stmt`: enum record payloads lost their defining package. Payloads now
  use declaration scope before generic substitution.
- `dump_for_clause`: a returning arm has type `never` and must not conflict
  with another arm's value type. Valid and invalid return cases are tested.
- `base.parse_flags`: a global initialized by a factory retained an unqualified
  return type. Function binding qualification now precedes global inference;
  the native regression passes.

The latest diagnostic component checks the complete 268-file source in
33.18 seconds, peak 1033196 KiB, then rejects `continue` in
`src/cmd/compile/internal/base/hashdebug.s:115` (`base.split`). The shared
canonical statement AST currently has no loop-jump variant. Fixing this needs
real parser, semantic and CFG handling, including loop-carried values and
C-for post execution. Accepting `continue` as an untyped name or skipping the
statement would be incorrect. This is the next FIRST RED.

These small native diagnostic components locate the first failing function.
They are not Stage2 builds or convergence evidence.

## Full native measurements

The earlier frozen 268-file Stage1 (hash
`78c1696a1c863896df617ed5e825a05df9c47ad969896bc25fb3eb50951d77d8`)
passed native verification, scalar and scalar-enum programs returning 42.
Stage1 compiled its exact frozen closure: parser 22.306 seconds, semantic
rejection 39.528 seconds, exit 1 at 39.578 seconds, peak 1025748 KiB.

A further full 268-file Stage1 was independently rebuilt under
`.bootstrap/selfhost-scope-final/`, using immutable source files and a source
hash manifest. Seed compilation took 180.24 seconds (peak 671704 KiB); native
emission took 344.69 seconds (peak 712176 KiB). The resulting ELF passed
`verify_true_selfhost.sh` and has SHA-256:

```
19a20ad35ee1c7116d81c908b04315cb7f5ba221a369f2697b541905aad652b2
```

It passed the native tuple and external-contract production regressions and
compiled the three-package `test/selfhost/nominal-scope/` control, executing 42.
Its real Stage1→Stage2 run parsed in 22.524 seconds and rejected in 45.525
seconds, exit 1, peak 1033228 KiB (1009.0 MiB). This frozen version predates
the later enum-shadow/payload/switch fixes. It rejects with e3010, consistent
with the diagnostic `dump_const` frontier. This is rejection time, not a
successful compilation time. Actual phase/RSS samples are retained in
`.bootstrap/selfhost-scope-final/after-measurements.json`.

The latest frozen full 268-file build is in
`.bootstrap/selfhost-scope-latest/`. Its trusted C seed was compiled with `-O2`;
S compilation still emits native amd64 directly. Seed native compilation took
162.14 seconds (675668 KiB), native emission 221.31 seconds (712900 KiB).
The Stage1 ELF passed native verification with SHA-256:

```
3f72692b031125562a2885a4137dcae118ae785591d2b22b6ce5f5a6d653e99b
```

All 268 immutable input hashes were rechecked. The real Stage1→Stage2 run
parsed in 22.602 seconds, rejected with e3010 in 46.562 seconds, exit 1,
peak sampled RSS 1033612 KiB (1009.4 MiB). The identical complete-source
semantic component narrows this error to the `continue` in `base.split`.
Eight native production groups (semantic, external contract, record, array,
bool, CFG, store, tuple) passed with this actual full Stage1, plus the
three-package nominal-scope program executing 42. Ten parser groups and six
semantic groups passed on the frozen latest sources. This is still a rejected
Stage2 compilation; it is not evidence of Stage2/Stage3 convergence.

## Regression status and limits

The strengthened snapshot test counts 2005 aggregate snapshots with the
pre-change seed and 5 with the repaired seed. Global temporary cleanup,
argument evaluation ordering, nested global aliases and independent value
mutation pass under 64 MiB. Record borrows, receiver mutation and loop liveness
regressions passed again after the scope changes.

The missing `program_environment.s` dependency was added to the production
compiler closure (now 100 modules). The canonical production suite advances
through its CFG tests, then rejects the C-for early-return fixture's statically
unreachable `10 / 0` post expression (e3065). The later native store regression
passes separately; the tuple regression passes with the new full Stage1.
The separate `option[expr]` fixture remains tracked; it was not the measured
cause of the original memory growth.

Concurrent external resets repeatedly removed working changes. Diagnostic
validation therefore uses `.bootstrap/scope-validation/`, an independent source
snapshot with hashes. Build snapshots remain immutable; changes are never
attributed to a binary built from an earlier revision.

No Stage2 executable was produced, Stage3 was not run, and no convergence or
completion marker was created. Selfhosting remains incomplete.
