# S Programming Language

S is a systems programming language and compiler project working toward full self-hosting. The repository contains the seed compiler, the S frontend and backend, the runtime, standard-library packages, architecture support, and compiler tests.

## Methods and interfaces

S uses receiver methods as its single core method model:

```s
func (file* writer) write(string data) ((), io_error) {

}
```

Traits are satisfied implicitly by method-set compatibility. A type implements a trait when its receiver methods contain every method required by that trait with compatible parameter and return types.

## Compiler ownership and lowering

`make compiler` builds the P0 Native compiler and retains an explicit legacy
ownership checker and C backend for a separate language subset. It supports owned integer boxes, moves, lexical
shared/mutable borrows, branch checks, and automatic cleanup on scope exit,
return and loop control. Generated applications do not link the S GC.

```sh
./misc/scripts/s-compiler.sh build --legacy test/compiler/ownership.s -o /tmp/s-owned
make compiler-check
```

See [the compiler guide](doc/compiler.md) for the supported syntax, tests and
limitations. The compiler is seed-hosted; this is not yet full-language or
converged self-hosted ownership-aware compilation.

## Performance status

P0 prioritizes correct native code generation; no broad performance claim is made.
The explicit legacy benchmark path lowers supported S programs to C and uses the
host C compiler. Generated applications are checked to avoid S GC and seed
interpreter dependencies.

Use `make benchmark` to compare the no-GC S benchmark with C, Rust when
`rustc` is available, and Go when `go` is available. Treat the result as local
measurement data rather than a project-wide performance claim. The immediate
goal is correctness, deterministic cleanup, and regression tracking; broad
performance claims need repeated benchmarks across realistic workloads.

## Repository layout

- `src/cmd/compile/seed`: C-based seed compiler and runtime.
- `src/cmd/compile`: self-hosted S compiler implementation.
- `src/runtime`: language runtime implementation.
- `src/std`: core standard-library packages.
- `src/net`: networking packages and native socket support.
- `test`: syntax, ABI, lexer, and compiler tests.
- `misc`: editor support and development utilities.

## Host and target platforms

S follows Go's host/target split. `S_HOST_OS` and `S_HOST_ARCH` describe the
machine executing the compiler; `S_TARGET_OS` and `S_TARGET_ARCH` describe the
binary being produced. They need not be equal for compilation, but a bootstrap
stage can execute only on its target or through `S_BOOTSTRAP_RUNNER`.

The verified P0 Native target is **Linux/amd64 ELF**. Other architecture and bootstrap
experiments are separate from P0 acceptance and do not establish full self-hosting.

Inspect the active target with:

```sh
make target-info S_TARGET_OS=linux S_TARGET_ARCH=amd64
```

See [`doc/platforms.md`](doc/platforms.md) for the support matrix and the
requirements for adding a target.

## Requirements

- Linux or macOS for the C seed compiler
- GNU Make
- A C11-compatible compiler such as GCC or Clang

For native self-hosting, the target is currently Linux/amd64 and requires GNU
binutils. When cross-building on macOS, Homebrew's `x86_64-elf-*` tools are
selected automatically; set `S_BOOTSTRAP_RUNNER` to a Linux/amd64 executor to
run stage1, stage2, and stage3.

## Build the seed compiler

```sh
make seed-compiler-bin
```

This produces `bin/s_seed`.

Compile an S source file to IR:

```sh
./bin/s_seed input.s output.ir
```

## Compile a Native program

The default Linux/amd64 build now consumes structured function MIR and SSA.
P0 supports straight-line int64/void functions, direct calls, arithmetic, bindings
and returns. Unsupported syntax is rejected; there is no implicit C or interpreter
fallback. See [the Native codegen guide](doc/native-codegen.md) for ABI and limits.

```sh
make compiler
./bin/s build test/native-build/program.s -o /tmp/s-native-demo
/tmp/s-native-demo 7
# exit status 25
/tmp/s-native-demo 2
# same executable, exit status 10
./bin/s --emit-amd64 test/native-build/program.s /tmp/demo.s
./bin/s --emit-native-object test/native-build/program.s /tmp/demo.o
make native-codegen-check
```

Existing ownership/C compilation remains available explicitly, including programs
that use printing and other constructs outside P0:

```sh
./bin/s build --legacy test/cli/hello.s -o /tmp/s-hello
/tmp/s-hello
```

## Self-hosting status

Latest verification (2026-10-29): eight backend helper return signatures now
explicitly match their tagged `result[...]` bodies and consumers. All 40
production checks pass. Complete-source Stage1 next stops at e3020 in
`build_object_interpreted_legacy`. See
[the current blocker and measured evidence](doc/selfhost-result-contract-20261029.md).

Full native self-hosting is not yet verified. The current compiler is seed-hosted;
P0 Native output contains neither the seed compiler nor its interpreter runtime.
That distinction does not mean the compiler can yet compile its complete source.

Bootstrap scripts and `make selfhost` are experimental. Acceptance still requires
complete-source compilation, removal of launcher/interpreter delegation, and a
verified stage1 → stage2 → stage3 chain. See
[the pipeline status](doc/compile-pipeline-status.md) for remaining work.

## Runtime foundation

The S runtime foundation is exposed from `src/runtime/runtime_foundation.s` and
`src/runtime/select.s`. It provides the common contracts for typed allocation
and collection, scheduler steps, channel send/receive selection, segmented
stacks, defer/panic/recover state, reflection type descriptors, syscall
dispatch, profiling samples, and race hooks. `src/runtime/chan.s` and
`src/runtime/proc.s` contain the corresponding queue and scheduler fixes.

These contracts are intentionally separate from target-specific intrinsic
lowering. Production support still requires each target backend to implement
the declared intrinsic ABI and the compiler to emit stack maps and safe-point
metadata; the presence of an S API alone does not claim that work is complete.

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
make compiler-check
make benchmark
```

`make benchmark` builds the no-GC S benchmark beside C, Rust when `rustc` is
available, and Go when `go` is available. Treat its output as measurement data:
do not claim S is faster than Rust or C unless repeated runs on the target
machine support that claim.

Use `make help` to list the primary build and test targets.

## License

See the repository license files for licensing terms.
