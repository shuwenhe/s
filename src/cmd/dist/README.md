# S toolchain builder

`cmd/dist` owns construction of the S toolchain. This follows the same boundary
as Go: compiler implementation belongs to `cmd/compile`, object encoding belongs
to `cmd/internal/obj`, linking belongs to `cmd/link`, and staged toolchain
construction belongs here.

The stages are build provenance, not compiler architecture:

1. the trusted C seed builds the current S compiler sources;
2. the resulting S compiler builds the second toolchain;
3. the second toolchain builds the third toolchain;
4. normalized second- and third-stage artifacts must converge;
5. the installed compiler must contain no C seed or IR-interpreter dependency.

Current convergence is IR-only and seed-hosted. `make true-selfhost-check`
remains the release gate for a native self-hosted compiler.

Compiler sources must use these declaration forms:

```s
x := 10
const y := 5
int z = 15
```

`let` and `var` are not declaration keywords.
