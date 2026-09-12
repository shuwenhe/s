# S Programming Language

S is a systems programming language and compiler project working toward full self-hosting. The repository contains the seed compiler, the S frontend and backend, the runtime, standard-library packages, architecture support, and compiler tests.

## Methods and interfaces

S uses receiver methods as its single core method model:

```s
func (writer* File) write(string data) ((), io_error) {

}
```

Traits are satisfied implicitly by method-set compatibility. A type implements a trait when its receiver methods contain every method required by that trait with compatible parameter and return types. S does not use `impl` declarations.

## Compiler ownership and lowering

`make compiler` builds an S-written ownership checker and C backend for
an explicit language subset. It supports owned integer boxes, moves, lexical
shared/mutable borrows, branch checks, and automatic cleanup on scope exit,
return and loop control. Generated applications do not link the S GC.

```sh
./misc/scripts/s-compiler.sh build test/compiler/ownership.s -o /tmp/s-owned
make compiler-check
```

See [the compiler guide](doc/compiler.md) for the supported syntax, tests and
limitations. The compiler is seed-hosted; this is not yet full-language or
converged self-hosted ownership-aware compilation.

## Performance status

S is not yet claiming to outperform Rust or C. The current no-GC compiler path
is intentionally small and measurable: supported S programs are lowered to C,
compiled with the host C compiler, and checked so generated binaries do not
link the S GC or the seed interpreter runtime.

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

The independently executable compiler backend is **Linux/amd64 ELF**. On an
Apple Silicon Mac, `make darwin-arm64-hosted-compiler` builds a native
`Mach-O/arm64` compiler whose compiler program is `compiler.s`; its bootstrap
runtime is still supplied by the trusted C seed. It is therefore a native Mac
compiler, but not yet a C-free, converged S self-host chain. Direct Mach-O
code generation begins with `make darwin-arm64-slice-check`: its ARM64
instruction selection is implemented in `compiler.s` and produces a runnable
Mach-O binary for the arithmetic/call bootstrap slice. The Darwin self-host
runtime and the remaining language constructs remain the next frontier.

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

## Compile a program (GCC-style command line)

### Example: Hello World

Here's a simple S program that demonstrates the feature:

```s
package main

func main() {
    println("Hello, world!")
    int i,j
    i = 10
    j = 20
    println("i + j =", i + j)
    count := 100
    int sum = 0
    for i := 0; i < count; i++ {
        print("i =", i)
        sum += i
    }
    println("sum =", sum)
    return
}
```

To compile this program:

```sh
s hello.s                 # writes ./hello
./hello
s hello.s -o hello        # explicit executable name
./hello
s -o hello hello.s        # -o may also precede the input
```

After `make selfhost`, add the compiler to your current shell's PATH:

```sh
export PATH="$PWD/bin:$PATH"
cp test/cli/hello.s hello.s
s hello.s                 # writes ./hello
./hello
s hello.s -o hello        # explicit executable name
./hello
s -o hello hello.s        # -o may also precede the input
```

The existing `s build hello.s -o hello` command remains supported. Run
`s --help` for basic usage and `sh test/cli/check.sh` for CLI regression checks.
This interface compiles one S source file using the existing Linux/amd64 native
backend and its supported language subset; it does not compile C/C++ sources
or implement the full GCC option set.

The default driver uses the ownership compiler path for supported programs:
S source is lowered to C, then the host C compiler links it with
`src/runtime/compiler_runtime.h`. That runtime boundary uses ownership and
explicit drops; generated binaries are checked to avoid S GC and seed runtime
symbols.

## Build the native self-hosted compiler

```sh
make selfhost
```

The resulting compiler is installed as `bin/s`. The C seed is used only to
construct stage1; stage1 generates stage2 and stage2 generates stage3. Host
`as`/`ld` link the generated native artifacts, but the C seed is not used to
generate stage2 or stage3.

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
`make native-bootstrap` verifies the staged chain and stage2/stage3
convergence. The C seed is used only for stage1.
The complete direct S-to-ELF convergence target is `make direct-bootstrap`; it
is intentionally a failing gate until the complete compiler source is within
the direct native-code-generation subset. See [`doc/bootstrap.md`](doc/bootstrap.md)
for the verified state, gaps, and production acceptance plan.

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
