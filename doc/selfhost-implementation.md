# Compiler self-hosting design

Updated: 2026-10-23. The user selected completion of the existing native
pipeline, with complete-source three-stage convergence as the acceptance
criterion. This document is the design for that work; the compiler is not
currently self-hosting.

## Outcome and scope

The compiler must compile its complete production source into a native stage1,
then repeat that compilation without the C seed. Stage1 builds stage2, stage2
builds stage3, and the stage2/stage3 assembly artifacts and ELF files compare
byte for byte. Stage3 must also compile and run an independent program.

The supported bootstrap target is Linux/amd64. The seed is trusted only to
build stage1. Later stages may invoke the assembler and linker, but must not
invoke a source compiler, C backend, interpreter, or forwarding launcher.
The implementation extends the existing S-written native frontend, MIR, SSA,
and amd64 emitter. It does not replace them with the historical bootstrap
backend or a separate minimal compiler.

The production closure is obtained from `source_closure.sh`, with no
self-host-only source substitutions or declaration filtering. Every file
must be parsed and checked. Dead code may be omitted from machine output
only after validation. Language features needed by the closure belong in
scope; unrelated targets, optimizations, and standard-library expansion do not.

## Verified baseline

At commit `6ef09d4cc`, the current production closure contains 252 files.
The 2026-10-23 run of `make selfhost` fails during seed compilation, before
stage1 exists:

```text
src/cmd/compile/internal/parser/frontend_parser.s:152:5:
error[5]: unproven record borrow: escaping handle or unsupported call/body
```

The statement is `p.peek_token = lexer_next_token(p.lexer*)` inside
`parser_next_token`. The parser represents the postfix `*` as a unary
expression; the borrow proof currently has no corresponding field-reborrow
case. This is a concrete investigation target, not evidence that allowing
that syntax alone is a sufficient or sound fix.

`make selfhost-native-record-check` and `make selfhost-protocol-check` both
exit successfully. They cover pointer parameter orders, package identities,
record copying, recursive ASTs, reborrows, invalid ownership/forged IR,
artifact validation, and native host services. The previous document's
pointer-parameter and package-scope work is already present in this baseline.

There is a second, independent barrier: `handle_compile_unit` calls
`native_source_to_mir`, then `lower_function_mir_to_ssa`, then
`emit_function_ssa_amd64`. These boundaries currently support integer/void
straight-line functions. The frontend rejects structures and control flow;
the lowering and emitter reject multi-block functions and aggregate types.
Producing stage1 alone therefore cannot establish self-hosting.

## Architecture and contracts

### Seed-to-stage1 ownership proof

Keep source validation and standalone IR validation independent. Extend
borrow provenance to explicit record field reborrows only when the owner,
referent declaration, lifetime, and exclusive call interval are proved.
The callee must mutate the actual field; replacing a reborrow with a copied
local record changes program behavior and is not acceptable.

Reject escaped handles, incompatible field types, overlapping exclusive
arguments, unproved resource owners, and effectful argument evaluation while
a borrow is pending. Unknown forms continue to fail. Native IR must encode
enough provenance for emission to reject forged or erased borrow metadata
without trusting a prior source check. No compiler-package exemptions apply.

### S frontend and executable MIR

Preserve package-qualified declarations, file-local imports, lexical bindings,
and source diagnostics. Collect declarations before lowering bodies so
recursion and declaration order work. Extend typed MIR operations and block
terminators alongside frontend support; do not encode executable constructs
as unverified source strings.

Control flow includes comparisons, short-circuit expressions, branches,
loops, break/continue, and early returns. MIR validation must check target
existence, operand types, definitions on all incoming paths, call signatures,
and terminators. Joins and loop-carried variables must have explicit values;
undefined variables on a predecessor remain errors.

### SSA and amd64 emission

Lower all MIR blocks, preserving control-flow edges and value identities.
Represent joins with predecessor-associated incoming values and verify
dominance and types. Emit deterministic block labels and predecessor-edge
copies, including cyclic parallel copies, so joins and loops execute correctly.
Keep stack layout, call alignment, register/stack arguments, and return
conventions consistent across direct and recursive calls.

Define layouts and operations for the strings, arrays, records, enums, and
multiple results actually used by the production closure. Value copies and
borrowed references need distinct lowering: record assignment snapshots its
value, while exclusive field access retains its proven owner. Generated
runtime support must implement those semantics and allocation/cleanup
contracts rather than borrowing the seed interpreter's object model.

### Native runtime and host services

Provide target assembly/runtime implementations for the intrinsics required
by reachable compiler code: arguments, environment, strings/containers,
allocation, source reading, output writing, process execution, and filesystem
operations. Reuse existing native runtime implementations where their ABI and
ownership contracts match; expose them through explicit lowering rules.
Unknown externs and mismatched intrinsic signatures fail before output is
installed. Source paths and symbols must not be interpolated into shell code.

### Bootstrap acceptance and output integrity

Retain the `S-NATIVE-AMD64-V1` assembly boundary and standalone ELF audits.
Each stage consumes the same ordered source closure. Failed compilation
preserves any prior output and invalidates success evidence for the current
bootstrap attempt. Final installation of `bin/s` occurs only after all
convergence, artifact-audit, and independent-program checks succeed.

The current bootstrap script compares stage2/stage3 but does not run the
independent program. Add that acceptance gate before its `.complete` marker
and before `make selfhost` installs stage3; retain all existing gates.

## Delivery order and tests

1. **Field-reborrow frontier.** Add a failing native execution regression for
   the parser/lexer field mutation pattern, then implement the smallest sound
   source-and-IR change. Include negative tests for aliasing the parent and
   child, escaping the child, type mismatch, and forged external IR. Run the
   record suite and rerun `make selfhost`; record the next concrete failure.
2. **Complete-source stage1.** Resolve subsequent seed/native runtime blockers
   one at a time, each with a regression. Check the entire resolved closure,
   emit standalone stage1, and audit it. Stage1 must compile and execute an
   independent integer program before claiming this milestone.
3. **Executable control flow.** Extend frontend, MIR validation, SSA, and
   amd64 together. Execute nested branches, loops with variable joins,
   short-circuit side effects, early returns, and break/continue. Reject
   invalid targets, missing definitions, incompatible joins, and bad calls
   even when MIR or SSA is supplied directly.
4. **Compiler value types and runtime.** Extend the same boundaries with
   typed layouts, aggregate operations, constants, enums, switches, methods,
   and required intrinsics. Verify actual native results for copying,
   mutation, recursion, strings, arrays, and calls with stack arguments.
   Maintain ownership rejection tests and atomic output behavior.
5. **Three-stage acceptance.** Run `make selfhost` from fresh stage outputs.
   Audit each compiler ELF, compare stage2/stage3 assembly and binaries, and
   have stage3 compile/run an independent source whose result depends on its
   command-line input. Test at least two inputs so a precomputed answer does
   not satisfy the gate. Audit that executable as well. Install stage3 only
   after the complete protocol passes.

The immediate implementation plan covers the field-reborrow frontier. Later
milestones retain this design's contracts and require concrete plans based on
the failure reached. Passing an intermediate milestone must be reported as
partial progress, never as completed self-hosting.

## Evidence to retain

Keep each bootstrap attempt's ordered source list, compile/emission/audit
logs, assembly artifacts, ELF files, comparison results, and smoke-test
statuses under its bootstrap output directory. Update project status from
those artifacts. Historical self-hosting reports describe different source
and backend states and do not substitute for the current acceptance run.
