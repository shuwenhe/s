# Native self-hosting: string ordering (2026-10-29)

The subsequent if/never fix and latest frontier are recorded in
[selfhost-if-never-20261029.md](selfhost-if-never-20261029.md).

The recorded `break` frontier is already implemented in this checkout. A fresh
native compiler passed all 20 break programs, eight dynamic inputs and three
outside-loop rejection cases. Continue, unit-shadowing and tuple-tail regressions
also passed before this change.

## Reproduced blocker and fix

The production compiler accepted the complete 268-file input through parsing,
then rejected it with `e3019: ordering compare requires int`. The minimal native
reproduction was `ch := "4"; if ch >= "0" && ch <= "9" { return 42 }`.
The first matching source function is `compiler_digit` in
`src/cmd/compile/internal/compiler/frontend.s:13`.

MIR lowering, MIR verification, SSA verification and AMD64 emission already
implement `string_lt`, `string_le`, `string_gt` and `string_ge`. The missing rule
was in `canonical_binary_inference`: it rejected two string operands before
lowering. The fix accepts that exact pair and retains the integer rule and
rejection of mixed-type and boolean ordering. No backend or ownership rules
were changed.

The new `canonical_string_order_production_check.sh` first failed with e3019,
then passed using the rebuilt native compiler. It executes nine fixed programs
and three dynamic inputs, and rejects twelve invalid comparisons without
replacing the output. Cases cover all four operators, equality, prefixes, empty
and default strings, unsigned non-ASCII bytes, concatenation and signed integers.
It is included in `make selfhost-canonical-production-check`.

The production suite also exposed an existing conflicting early-return fixture:
its unreachable loop post expression contained literal `10 / 0`, rejected by
the existing constant-zero check (e3065). The fixture now takes a runtime divisor
and is called with zero, verifying the intended post-skipping behavior without
requiring the semantic checker to accept constant division by zero.

## Full-source measurement and next frontier

Native production compiler, same 268-file closure:

| Run | Elapsed | Peak RSS | Result |
| --- | ---: | ---: | --- |
| Before fix | 54.409 s | 1059876 KiB | e3019 |
| After fix | 56.071 s | 1059952 KiB | e3015 |

After the fix, full-source compilation advances to `e3015: if/else type mismatch`.
A separate diagnostic native semantic component locates this in `compiler_next`
(`src/cmd/compile/internal/compiler/frontend.s:69`), reporting branch types
`()`/`never` and `never`/`()`. The minimized unresolved fixture is
`test/selfhost/if-never-merge/main.s`. This change does not alter branch typing.

Logs, source closure, frozen patched source hashes and measurements are in
`.bootstrap/selfhost-current/`. Stage2/Stage3 convergence remains unproven;
no completion marker is produced.

## Complete-source Stage1 confirmation

A separate optimized trusted seed compiled a frozen copy of all 268 patched
sources into native Stage1. All frozen source hashes were checked against the
working source. Build time was 500.030 s, with peak RSS 723028 KiB. The ELF passed
`verify_true_selfhost.sh` and both the complete string-ordering and break native
regressions.

That complete Stage1 compiled the same frozen sources toward Stage2, completing
parsing and rejecting the next frontier with e3015 after 55.706 s (peak RSS
1060140 KiB). No Stage2 assembly or binary was generated, so Stage3 did not run.
Stage1 SHA-256:

```text
0a176f9b21a35e808f487dde2dbe12d2b1d0ebd7b61011aa9ac694ab20ef5ec6
```

The complete-source baseline Stage1 independently reproduced both e3019 for the
minimal string comparison and e3065 for the original constant-zero loop fixture.
The patched production suite (`make -o compiler selfhost-canonical-production-check`,
using the freshly rebuilt compiler) passed all 36 checks. Independent code review
reported no findings and reran the new regression successfully.

Final complete-source evidence is in `fixed-stage1-build.log`,
`fixed-stage1-check.log`, `fixed-stage2-compile.log`,
`fixed-stage1-measurements.json`, `fixed-stage2-measurements.json` and
`fixed-source-hashes.json` under `.bootstrap/selfhost-current/`.
