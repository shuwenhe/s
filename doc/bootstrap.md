# S Bootstrap Ladder

S follows Go's staged bootstrap shape: a trusted compiler builds stage 1,
stage 1 builds stage 2, and stage 2 builds stage 3. Acceptance requires stage
2 and stage 3 to converge and the installed compiler to have no C-seed
dependency.

## Main acceptance path

```sh
make native-bootstrap
make true-selfhost-check
```

The trusted C seed participates only in stage 1. Stages 2 and 3 are generated
by S compiler binaries from `src/cmd/compile/selfhost/compiler.s`. The driver
compares their assembly and executables, audits the resulting static compiler,
and runs native frontend and rope-string conformance programs expected to
return 42.

`make selfhost` installs the converged stage 2 artifact as `bin/s`.
`make seed-hosted-selfhost` retains the compatibility path and is not the
release-grade self-hosting proof.

## Incremental compiler slices

The narrower checks document and protect the language/backend frontier:

1. `bootstrap-slice1-check`: minimal compiler and executable generation.
2. `bootstrap-slice2-check`: expressions, control flow, and locals.
3. `bootstrap-slice3-check`: calls, loops, strings, arrays, multicalls, copy.
4. `bootstrap-slice4-check`: function control, logic, typed locals, large functions.
5. `bootstrap-slice5-check`: multicall and argument passing.
6. `bootstrap-slice6-check`: string comparison and branch-string assembly.

The complete compiler closes constructs that the earlier slices did not need:
negative literals, declarations with default initialization, `else if`, and the
full six-register calling frontier. Runtime concatenation uses immutable ropes,
and one-byte strings are interned so compiling the compiler does not exhaust the
bootstrap heap.

Run `make pure-s-bootstrap-check` for the implemented no-seed frontiers and
`make bootstrap-audit` for provenance and manifest output.
