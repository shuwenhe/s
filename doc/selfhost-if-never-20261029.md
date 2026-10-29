# Native self-hosting: if/never joins (2026-10-29)

The subsequent statement-boundary fix and latest measured frontier are in
[selfhost-boundary-20261029.md](selfhost-boundary-20261029.md).

## Reproduced blocker and semantic fix

The complete-source Stage1 from the previous string-ordering change rejects
`test/selfhost/if-never-merge/main.s` with e3015, as does the preserved production
compiler. Full-source diagnostics locate the same error in `compiler_next`
(`src/cmd/compile/internal/compiler/frontend.s:69`): branch types `()`/`never`
and `never`/`()`. The source uses structured loop exits and early returns.

The if checker checked both branches but compared their types directly and
always chose the then-branch type. Existing switch checking already excludes
`never` branches from its value join. Native `program_lower_if` also already
handles one or both branches terminating.

The fix changes only the if result join: select the else type when the then
branch is `never`; otherwise retain the then type, checking compatibility only
when the else branch also produces a value. Two `never` branches remain `never`.
Condition checking, both branches' errors, return validation, nominal type
compatibility, and conservative borrow/move merging are unchanged. No parser,
MIR, SSA, native backend, ownership or source-eligibility rules were relaxed.

## Regression evidence

`canonical_if_never_production_check.sh` first fails on the original e3015
reproducer, then passes with the rebuilt native compiler. Fifteen programs run
with two inputs each (30 executions): the original case; both branch orders for
break, continue and return; surviving integer, string, record and boolean values;
nested if expressions; both-terminated branches; and outgoing binding values.
Nine invalid programs are rejected while preserving prior output, covering
incompatible live branches, invalid returns/names, a wrong surviving result,
an invalid condition, and break/continue outside a loop.

The script is included in `make selfhost-canonical-production-check`. The full
suite passed all 37 checks using the freshly rebuilt compiler
(`make -o compiler selfhost-canonical-production-check`). Independent review
reported no actionable findings in the branch join or its lowering interactions.

## Full-source progress and next frontier

The rebuilt native production compiler parsed the full frozen 268-file compiler
source set, passed the previous if/never error, and rejected the next error:
`e3018: arithmetic requires int` (60.379 s, peak RSS 1067656 KiB).

A separate diagnostic native semantic component locates this in
`compiler_struct_field_struct`, `src/cmd/compile/internal/compiler/frontend.s:703`.
Its final `-1` follows an if statement on a new line. The expression parser
consumes the minus as infix subtraction from the if expression, producing
operand types `()` and `int`. This is a separate parsing frontier; arithmetic
checking remains strict. The preserved minimal fixture is
`test/selfhost/newline-negative-tail/main.s`: the seed compiles it to native code
returning 42, while the canonical compiler rejects it with e3018.

Evidence, frozen sources, per-file hashes and complete-stage measurements are
under `.bootstrap/selfhost-if-never/`. Stage2/Stage3 convergence remains unproven;
no completion marker is produced.

## Complete-source Stage1 confirmation

The optimized seed built native Stage1 from all 268 frozen patched source files.
All per-file hashes match the working compiler source. Seed-to-IR took 164.985 s;
native emission took 353.445 s; total build time was 518.430 s, with peak RSS
723172 KiB. The ELF passed native verification and the if/never, break and continue
native regression suites. Its SHA-256 is:

```text
671f3f48687f278a16ffc908988383a8c7897001ca113d3b149fb7cb55ef09a4
```

This complete Stage1 then compiled the same frozen sources toward Stage2,
finished parsing and semantic checking up to the next rejection, and exited 1
with e3018 after 59.868 s (peak RSS 1067808 KiB). The former e3015 is cleared.
Stage2 assembly/binary were not produced; Stage3 and convergence remain unproven.

Raw evidence: `stage1-build.log`, `stage1-check.log`, `stage2-compile.log`,
`stage1-measurements.json`, `stage2-measurements.json`, `source-hashes.json`,
`before.json`, and `diagnostic/run.log` under `.bootstrap/selfhost-if-never/`.
Production suite output is preserved in `/tmp/s-if-never-production.log`.
