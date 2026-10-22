Current record ABI status (2026-10-22): `make selfhost-native-record-check`
checks eligible record values, nested copies, defaults, array recursion,
argument order, callee-saved registers, and allocation rollback. It is a
component check, not proof of selfhosting. The full 253-file source closure
currently fails native eligibility at `ir/dfa.s:28` (`int_set*`); pointer
borrow/lifetime contracts remain unproven. Both native bootstrap entrypoints
use `--compile-native-unit` so this rejection happens before IR output.
Full-source native Stage1 and Stage2/Stage3 convergence remain unproven.

# S distribution bootstrap tools

The canonical `make selfhost` entrypoint uses
`native-bootstrap-no-manifest.sh`. It resolves the production source closure,
uses the C seed's `--emit-standalone-amd64` for stage1, and requires every
compiler binary to pass `verify_true_selfhost.sh`. Stages 2 and 3 exchange
`# S-NATIVE-AMD64-V1` assembly artifacts (`.sasm`); both assembly and executable
bytes must converge. A failed rerun removes `.complete` before doing any work.

The S `--compile-unit` implementation currently supports the native integer/void
subset in a single package, including multiple source files and forward calls.
It rejects unsupported syntax and additional packages. The complete 253-file
production closure now emits an independent static stage1 that passes the
structural verifier. Local backend helper prefixes avoid flat-symbol clashes,
and the standalone linker discards unreachable functions and literals without
dropping their source files from the compilation unit.

Full self-hosting remains blocked at execution: the seed native backend's
flattened record slots do not preserve nested fields across function calls.
The resulting stage1 crashes in `native_advance` while accessing
`state.lex.error`, even for a small integer input. The native frontend also
needs imports, strings, arrays, records, and control flow before it can rebuild
the full source closure. In addition, native process/file service intrinsics
still need implementation fixes. Emission now rejects the temporary-directory
fallback before writing or cleaning the destination directory. Source reads reject embedded NUL and files larger
than the current 16 MiB buffer instead of accepting a truncated prefix.

For testing the S CLI while these native gaps remain, the seed provides explicit
`--emit-hosted-program INPUT.ir OUTPUT`. This interpreter-backed diagnostic
runner passes all arguments to the S main function. It does not intercept
`--emit-bin` or invoke the seed's emitter on behalf of S. It is never accepted
by the native bootstrap verifier. The older seed `--emit-bin` compatibility
runner retains its existing CLI behavior.

Run the protocol, source-dependence, independent ELF, and rejection checks with:

```sh
make selfhost-protocol-check
```

The still-failing execution frontier is reproduced by
`make selfhost-native-stage1-check`: it builds and verifies native stage1,
checks the temporary-directory rejection, then attempts native compilation of
a small program. Passing ELF inspection alone is not execution proof.

The following describes the older manifest-based driver:

This directory contains the staged native bootstrap driver and its audit
helpers. `native-bootstrap.sh` uses the trusted C seed only for stage 1, then
requires the S compiler to produce stages 2 and 3 and verifies both IR and
binary convergence.

The S-written controller in `bootstrap.s` uses the production import closure
from `source_closure.sh` and invokes the previous stage for both compilation
and emission. Run from the repository root, with absolute paths and a new
output directory whose parent already exists:

```sh
make s-dist-bootstrap-bin
.bootstrap/s-dist/s-dist-bootstrap "$PWD" "$PWD/.bootstrap/s-dist/run-001" "$PWD/bin/s_seed"
```

The controller retains failed artifacts, reports the failing stage and child
exit status, checks nonempty IR and executable ELF, prints producer/artifact
SHA-256 values, and compares raw stage2/stage3 IR and binaries. Its executable
currently uses the Seed host runtime for process and file services. Building
the controller does not establish compiler self-hosting. Byte equality alone
does not establish IR-to-Native authority; that remains a separate gate.

Run the supported entrypoints through the repository makefile:

```sh
make native-bootstrap
make true-selfhost-check
make bootstrap-audit
```
