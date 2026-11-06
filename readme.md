# S Programming Language

S is a systems programming language and compiler project working toward full self-hosting. The repository contains the seed compiler, the S frontend and backend, the runtime, standard-library packages, architecture support, and compiler tests.

## Methods and interfaces

S uses receiver methods as its single core method model:

```s
func (file* writer) write(string data) ((), io_error) {

}
```

Traits are satisfied implicitly by method-set compatibility. A type implements a trait when its receiver methods contain every method required by that trait with compatible parameter and return types.

## Build and run

The verified native target is Linux/amd64 ELF. Install Git, GNU Make, a C11
compiler, GNU binutils, Bash and Python 3, then run:

```sh
make compiler
./bin/s build test/native-build/program.s -o /tmp/s-native-demo
/tmp/s-native-demo 7
# exit status 25
```

`make compiler` builds the C seed and a seed-hosted native development compiler.
It does not perform a fresh multi-stage self-host verification. See the
[compiler guide](doc/compiler.md) for installation, CLI commands, a first program
and the additional acceptance dependencies.

Continue with the [native language tutorial](doc/tutorial.md) and its executable
example for arrays, receiver methods, generics, tuples and enum matching.

The default native path uses structured MIR and SSA and rejects unsupported
constructs. The explicit `build --legacy` path uses an ownership checker and C
backend for a separate language subset. Its memory model and feature coverage
differ from the canonical native compiler; see the [native backend guide](doc/native-codegen.md).

## Performance status

Correctness, reproducibility and regression coverage take priority. Historical
self-host measurements are recorded with the acceptance evidence. No broad
performance comparison with C, Rust or Go is established. Native code and the
legacy C path must be measured separately, recording compiler revision, toolchain,
workload, repeated execution time and peak memory.

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
The canonical path supports int64, bool, string, unit, records, supported arrays,
enums, generics and control flow, subject to semantic and lowering validation. Unsupported syntax is rejected; there is no implicit C or interpreter
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
bash test/native-codegen/check.sh
```

Existing ownership/C compilation remains available explicitly, including programs
that use printing and other constructs outside P0:

```sh
./bin/s build --legacy test/cli/hello.s -o /tmp/s-hello
/tmp/s-hello
```

## Self-hosting status

Native self-hosting is verified on Linux/amd64 (2026-11-03): C seed → native
stage1 → stage2 → stage3, using the complete 268-file compiler closure. Stage2
and freshly compiled stage3 have byte-identical assembly and executables.
The full production regression suite and native validator rejection tests pass.
These are historical results at the revision in the report. Development builds
replace `bin/s_compiler`; its filename does not certify a Stage3 artifact. Preserve
accepted binaries and logs in their evidence directory.

See [the verification report](doc/selfhost-verification/native-selfhost-2026-11-03.md)
for checkpoint provenance, hashes, measured results and reproduction commands.
For new acceptance use the [clean-room controller](doc/selfhost-verification/cleanroom.md)
from a committed revision and a new evidence directory. `make selfhost` is a
development bootstrap target and does not by itself perform full clean-room
acceptance. Complete staged builds can take hours. The ongoing
[production audit](doc/production-readiness/status.md) records remaining blockers.

`make PREFIX="$HOME/.local"` (or simply `make` with the default prefix) runs Seed → Stage1 → Stage2 →
Stage3 → Stage4 and installs Stage4 with the public `s` driver. All later stages
must pass native execution checks and Stage2/3/4 must converge byte for byte.
`make selfhost-install` remains a compatibility alias. Use
`make native-bootstrap-imports` to build without installing outside the checkout.

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

Run canonical production regression and controller tests:

```sh
make selfhost-canonical-production-check
python3 -m unittest discover -s test/bootstrap-reproducibility -v
bash test/native-codegen/check.sh
```

Additional seed/native record and memory checks are available:

```sh
make selfhost-native-record-check
make selfhost-native-memory-check
```

These targets have different coverage; success in one does not establish success
in the others. Tests requiring child-process tracing need an environment that
permits `strace`. Do not skip tracing assertions to obtain acceptance.

Use `make help` to list the primary build and test targets.

## License

See the repository license files for licensing terms.
