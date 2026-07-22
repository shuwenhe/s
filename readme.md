# S Programming Language

S is a systems programming language and self-hosting compiler project. The repository contains the seed compiler, the S frontend and backend, the runtime, standard-library packages, architecture support, and compiler tests.

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

## Build the self-hosted compiler

```sh
make selfhost
```

The resulting compiler is installed as `bin/s`.

To verify compiler bootstrapping and lexer compatibility:

```sh
make selfhost-check
```

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
