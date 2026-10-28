# Current selfhost FIRST RED: break

Seed compiles this source to a native program returning 42. The current canonical
compiler rejects `break` as an undefined identifier (e3010). This mirrors
`src/cmd/compile/internal/codegen/amd64_program.s:248`, function amd64_emit_edge.
The source is an unresolved frontier fixture, not a passing regression.
