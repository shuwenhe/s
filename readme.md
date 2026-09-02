# S Programming Language

S is a systems programming language and compiler project working toward full self-hosting. The repository contains the seed compiler, the S frontend and backend, the runtime, standard-library packages, architecture support, and compiler tests.

## Methods and interfaces

S uses receiver methods as its single core method model:

```s
func (writer* File) write(string data) ((), io_error) {

}
```

Traits are satisfied implicitly by method-set compatibility. A type implements a trait when its receiver methods contain every method required by that trait with compatible parameter and return types. S does not use `impl` declarations.

## Repository layout

- `src/cmd/compile/seed`: C-based seed compiler and runtime.
- `src/cmd/compile`: self-hosted S compiler implementation.
- `src/runtime`: language runtime implementation.
- `src/std`: core standard-library packages.
- `src/net`: networking packages and native socket support.
- `test`: syntax, ABI, lexer, and compiler tests.
- `misc`: editor support and development utilities.

## Requirements

- Linux or macOS
- GNU Make
- A C11-compatible compiler such as GCC or Clang

## Build the seed compiler

```sh
make seed-compiler-bin
```

This produces `bin/s_seed`.

Compile an S source file to IR:

```sh
./bin/s_seed input.s output.ir
```

## Build the native self-hosted compiler

```sh
make selfhost
```

The resulting compiler is installed as `bin/s`. This is an intermediate native
bootstrap frontier: the installed binary is a static stage2 artifact, but C
seed builds stage1 and host `as`/`ld` build stage2. It must not be described as
an independently pure-S bootstrap yet.

To verify compiler bootstrapping and lexer compatibility:

```sh
make selfhost-check
```

To require that `bin/s` no longer links the C seed compiler, run:

```sh
make true-selfhost-check
```

This stricter check remains the release gate for catching any lingering seed
dependency in the installed compiler.

The executable bootstrap work and its acceptance criteria are documented in
[`doc/bootstrap.md`](doc/bootstrap.md). The first static pure-S frontend slice
can be exercised with `make bootstrap-slice1-check`.
For the seed-hosted compatibility path, use `make seed-hosted-selfhost`.
`make native-bootstrap` verifies the intermediate C-seed/host-linker path.
The complete direct S-to-ELF convergence target is `make direct-bootstrap`; it
is intentionally a failing gate until the complete compiler source is within
the direct native-code-generation subset. See [`doc/bootstrap.md`](doc/bootstrap.md)
for the verified state, gaps, and production acceptance plan.

## Tests

Run the seed compiler tests:

```sh
make seed-tests
```

Additional checks are available through:

```sh
make seed-runtime-regression
make seed-network-tests
make seed-c-abi-test
make selfhost-lexer-check
```

Use `make help` to list the primary build and test targets.

## License

See the repository license files for licensing terms.
