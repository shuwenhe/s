# Structured native source frontend

Run `bash test/native-frontend/check.sh` from the repository root. The test
seed-builds and executes the real S frontend, sharing the existing scanner but
without running the legacy C expression emitter or an AST interpreter.

The supported source boundary is one package, direct functions with integer
parameters, integer or void results, local integer bindings and assignments,
integer arithmetic, direct calls, and returns. The frontend records every
function before parsing its body so forward and qualified calls resolve.
Unsupported declarations, control flow, types and trailing source are rejected.

The runner checks parameter identity, unused functions, forward calls, void
calls, retained division/remainder instructions, source mutation, INT64_MIN,
21 functions and 25 rejection inputs, including canonical reserved words. It
also checks leading-zero INT64_MIN literals and negative literal overflow.
Native execution of the resulting SSA is
covered separately by the production and backend acceptance tests.

Initial RED: with the new frontend absent, the hosted runner failed with
`unknown function: native_source_to_mir`. GREEN: the complete hosted runner
prints `Structured native frontend: PASS`.
