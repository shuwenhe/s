# Native selfhost profile (2026-10-28)

Full selfhosting is not yet proven. Keep the Stage2/Stage3 convergence gate.

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

## First red and independent failures

Diagnostic tracing reveals repeated same-package intrinsic prototypes are
currently rejected as duplicate declarations (`__host_char_at`, `__host_slice`,
`__host_write_text_file`, `runtime_env_get`). Matching external contracts
must be distinguished from conflicting prototypes and ordinary definitions.
Matching same-package, same-library external contracts are now merged;
different parameter types, libraries and ordinary duplicate bodies remain
rejected by regression tests.

The next component FIRST RED was `token_kind_name`: comparing two values of
the same scalar enum incorrectly produced e3039. Contextual binary inference
now uses declaration identity for this case. Distinct enums, enum/integer
comparisons and payload enums remain rejected.

The broad canonical/protocol targets independently stop while building their
99-module compiler closure at:

```
unknown native record transfer type:
compile.internal.ir.lower.program_lower_state.environment (program_environment)
```

The pre-change diagnostic seed reproduces this failure. The separate
`option[expr]` fixture failure remains tracked; neither is the profiler's
explanation of Stage2 memory retention.

## Final full native verification

The final full 268-file Stage1 was rebuilt and passed `verify_true_selfhost.sh`.
It independently compiled, linked and executed both a scalar smoke program
and a scalar-enum equality program with exit 42. Its SHA-256 is:

```
78c1696a1c863896df617ed5e825a05df9c47ad969896bc25fb3eb50951d77d8
```

`.bootstrap/selfhost-profile-final/source/` contains the frozen compiler
inputs; `source-manifest.json` records all 268 source hashes. The real Stage1
compiled exactly that frozen closure. Parser completion was observed at
22.306 seconds; semantic rejection at 39.528 seconds; process exit 1 at
39.578 seconds. Peak sampled RSS was 1025748 KiB (1001.7 MiB).

The remaining full-source FIRST RED is `canonical semantic: e3011: unknown
member`. The diagnostic component narrows it to `dump_tokens` in
`lexer/token/token.s`: arguments to `std.prelude.to_string` have type
`unknown`, while the unit contains three distinct package-local `token`
records. The checker does not preserve the defining package of the
unqualified `token[]` parameter. `test/selfhost/nominal-scope/` is a minimal
control: Seed emits a native program executing 42, while the current S checker
rejects it. Resolving an arbitrary same-named record is not an acceptable fix.

A further independent pipeline RED remains for repeated matching intrinsic
prototypes: semantic checking merges the contracts, but MIR construction still
reports `duplicate function: main.__host_char_at`. The external smoke input
must not be described as a passing end-to-end test.

The strengthened snapshot test, including indexed-record mutation, counts
2005 aggregate snapshots with the pre-change seed and 5 with the new seed.
Borrow/receiver, nested global aliases, caller snapshot independence,
argument evaluation ordering, loop liveness, rope/lexer and canonical semantic
positive/negative regressions passed. Full canonical/protocol targets remain
blocked by the separately reproduced 99-module closure error above.

No Stage2 artifact/executable was produced, Stage3 was not run, and no
convergence/completion marker was created. This is a measured performance
repair and a new correctness frontier, not complete selfhosting.
