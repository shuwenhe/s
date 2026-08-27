# S toolchain builder

`cmd/dist` owns construction of the S toolchain. This follows the same boundary
as Go: compiler implementation belongs to `cmd/compile`, object encoding belongs
to `cmd/internal/obj`, linking belongs to `cmd/link`, and staged toolchain
construction belongs here.

The stages are build provenance, not compiler architecture:

1. the trusted C seed builds the current S compiler sources;
2. the resulting S compiler rebuilds the compiler sources;
3. the second compiler rebuilds the sources again;
4. normalized second- and third-stage artifacts must converge;
5. the installed compiler must contain no C seed or IR-interpreter dependency.

Current convergence is now native-first. `make selfhost` installs the native
bootstrap result, `make seed-hosted-selfhost` preserves the older compatibility
path, and `make true-selfhost-check` remains the release gate for a compiler
that no longer links the C seed.

Compiler sources must use these declaration forms:

```s
x := 10
const y := 5
int z = 15
```

`let` and `var` are not declaration keywords.
