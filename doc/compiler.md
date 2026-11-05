# Building and using the S compiler

The production native target is Linux/amd64. The compiler is self-hosting for its compiler source closure; this does not establish complete support for every construct in the historical syntax guide. See [current audit](production-readiness/audit.md) and [native backend](native-codegen.md).

## Build from source

Install Git, GNU Make, a C11 compiler, GNU binutils, Bash and Python 3. Full acceptance additionally requires Python YAML, ripgrep, strace, GNU time, file, coreutils, findutils and tar. On Debian/Ubuntu these correspond to git, build-essential, binutils, python3, python3-yaml, ripgrep, strace, time, file, coreutils and findutils.

From the repository root:

```sh
make compiler
./bin/s --help
```

This builds the C seed and a development native compiler from S sources. It is a seed-hosted build, not a fresh multi-stage self-host verification. Build logs enumerate source inputs. Generated files live in bin and .bootstrap.

For a fresh verified multi-stage build use the [clean-room controller](selfhost-verification/cleanroom.md), with a clean committed checkout and a new output directory. Do not reuse an existing acceptance directory. Tracing must be permitted for the build's own child processes.

## First program

Save this as demo.s:

```s
package main
func main(int value) int {
    return value * 3 + 4
}
```

Compile and run:

```sh
./bin/s build demo.s -o ./demo
./demo 7
# process exit status: 25
```

The integer return becomes the process exit status (the shell exposes its low eight bits). Use `echo $?` immediately after execution to inspect it. The executable is reusable with different integer arguments. A no-argument int or unit main is also supported by native startup.

## CLI

The checkout shell driver accepts `s input.s`, `s input.s -o output`, `s -o output input.s` and `s build input.s -o output`. Default output removes a terminal .s suffix; other inputs gain .out.

```sh
./bin/s --emit-amd64 demo.s demo.asm
./bin/s --emit-native-object demo.s demo.o
./bin/s_compiler --compile-unit demo.sasm demo.s
./bin/s_compiler --emit-bin demo.sasm demo
```

`--compile-unit` takes output first and accepts multiple source inputs. `--emit-bin` consumes emitted assembly; it does not re-read source. MIR and ownership diagnostic modes are listed by `./bin/s --help`.

`build --legacy` is an explicit shell-driver path through the legacy ownership/C subset. It requires a host C compiler and is supported only for that subset. Native builds reject unsupported constructs with no implicit legacy fallback. `make install` now installs the same public driver and native compiler in a versioned relocatable tree. Use PREFIX for the installation root and optionally INSTALL_BIN_DIR for its command directory. See the [installation guide](../S_INSTALLATION_GUIDE.md) for version, run, test, upgrade and uninstall contracts. Binary distributions omit the seed, so `--seed` remains a development-checkout mode.

## Verification and troubleshooting

```sh
python3 -m unittest discover -s test/bootstrap-reproducibility -v
make selfhost-canonical-production-check
bash test/native-codegen/check.sh
```

Production checks rebuild the development compiler. Preserve accepted stage binaries in a separate evidence directory before development builds. Missing dependencies fail explicitly. `PTRACE_TRACEME: Operation not permitted` means the execution environment prohibits tracing; rerun in an environment allowing child-process tracing, without skipping the checks. Parser/semantic errors include stage and location; unsupported native types may be diagnosed at MIR/SSA validation.

Do not use `make clean` to prepare an acceptance run: it removes development artifacts. The controller creates a new committed-source checkout itself.
