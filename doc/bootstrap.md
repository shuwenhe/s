# S Bootstrap

This document describes the bootstrap boundary for the S compiler and how it
compares with the Go toolchain bootstrap model.

## Reference model

Go bootstraps its toolchain in staged layers:

1. a trusted bootstrap toolchain builds the current sources;
2. the resulting toolchain rebuilds itself;
3. the next rebuild must converge with the prior stage;
4. the installed toolchain is accepted only after the comparison passes.

S follows the same shape, but the current implementation is still split into
two bootstrap tracks:

1. `bootstrap-convergence` and `selfhost` prove seed-hosted convergence;
2. `native-bootstrap` exercises the native S frontend/backend chain;
3. `true-selfhost-check` is the acceptance gate for a compiler that no longer
   links the C seed compiler.

## Current stages

### Stage 0

The trusted C seed compiler is built with:

```sh
make seed-compiler-bin
```

This produces `bin/s_seed`.

### Seed-hosted convergence

The current self-hosted launcher is built with:

```sh
make selfhost
```

This currently checks that:

1. `stage2.ir` and `stage3.ir` are identical;
2. the generated launcher passes the seed-dependency audit;
3. the lexer bootstrap slice still matches the seed token stream.

### Native bootstrap frontier

The experimental native chain is built with:

```sh
make native-bootstrap
```

This path is intended to mirror Go's stage progression more closely:

1. build stage1 from the seed;
2. build stage2 from stage1;
3. build stage3 from stage2;
4. compare the normalized outputs;
5. reject any compiler that still depends on the seed or the IR interpreter.

## Acceptance criteria

The compiler is considered fully self-hosted only when all of the following are
true:

1. `stage2` and `stage3` converge;
2. the final compiler does not embed seed compiler symbols;
3. the final compiler does not depend on the IR interpreter path;
4. the native bootstrap checks pass for the implemented bootstrap slices.

Until then, `selfhost` is a bootstrap-proven launcher, not the final native
compiler.
