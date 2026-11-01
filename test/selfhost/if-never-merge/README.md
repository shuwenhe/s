# If branch with a loop exit

This was the self-hosting e3015 frontier in `compiler_next`
(`src/cmd/compile/internal/compiler/frontend.s:69`). The original program mixes a
`break` branch (type `never`) and an updating branch (type `()`).

The if/never fix joins the surviving branch type, consistently with switch
checking and existing native lowering. This fixture now compiles natively and
returns 42. It is the first case in
`test/native-bootstrap-diagnostic/canonical_if_never_production_check.sh`, which
also checks both branch orders, return/continue, surviving values, both branches
terminating, and invalid programs. See `doc/selfhost-if-never-20261029.md`.
