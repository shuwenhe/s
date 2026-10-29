# Statement-leading if followed by a negative tail

This was the e3018 self-hosting frontier in `compiler_struct_field_struct`
(`src/cmd/compile/internal/compiler/frontend.s:703`). The Seed AST retained an
independent if statement and unary-negative expression; the canonical parser
incorrectly consumed the latter as infix subtraction from the if.

The statement-boundary fix parses a statement-leading if directly, matching Seed
statement dispatch. This fixture now compiles with the native production
compiler and returns 42. It is the first program in
`canonical_statement_boundary_production_check.sh`. Additional AST assertions,
legal multiline-subtraction controls, and strict unit/integer rejection checks
are in that script and `canonical_statement_boundary_ast_check.sh`.

See `doc/selfhost-boundary-20261029.md` for raw token/AST evidence and complete
self-hosting validation. Passing this fixture does not prove Stage2/Stage3
convergence.
