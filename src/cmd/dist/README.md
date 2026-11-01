# Current native bootstrap status (2026-10-25)

`make compiler` now builds a native 95-module S production compiler. Its CLI,
Public MIR producer and native build commands use the canonical syntax AST,
semantic checker, typed MIR, verified SSA and AMD64 emitter.
`make selfhost-canonical-production-check` passes eight native regression scripts.

Seed builds the complete 264-module native Stage1. That actual Stage1 compiles,
links and executes a scalar enum program: inputs 2 -> 42 and 7 -> 47; changing
the enum tag from 40 to 41 changes input 2's result to 43. Invalid enum programs
are rejected by Semantic; enum declaration identity and tags survive into MIR.

Full selfhosting is still incomplete. `make selfhost` currently fails in
Stage1 -> Stage2 at `canonical parser:16: unsupported top-level declaration: struct`
in `lexer/token/token.s`. Stage2/Stage3 convergence is not proven and `.complete`
is absent. Struct/receiver syntax, generic payload enum layout and the corresponding
record/string/array/CFG native lowering remain incomplete; unsupported declarations
must fail rather than be dropped. See `doc/native-selfhost-evidence-20261025.md`
for the actual artifacts, call chain, verification results and independent failures.

## Historical component notes (2026-10-22)

Current record ABI status (2026-10-22): `make selfhost-native-record-check`
checks eligible record values, nested copies, defaults, array recursion,
argument order, callee-saved registers, and allocation rollback. It is a
component check, not proof of selfhosting. The full 253-file source closure
now resolves imported record type names in each source file before merging the
unit and first fails body eligibility at `ir/middlend_ir_builder.s` (`ir_builder_build`)
(`ir_builder_build`). Record receiver methods and direct reborrows
between proved functions are supported, including loops and recursive call
cycles. The old syntax lexer now owns a string and a token value array, replacing
its raw allocations. Primitive pointer borrows, recursive AST pointer ownership,
multi-result borrowed functions and general allocation remain unproven; moving
the first diagnostic does not prove the AST builder can execute. Both native bootstrap entrypoints
use `--compile-native-unit` so this rejection happens before IR output.
Native source mode supports a restricted, proved nonescaping record borrow:
loop-capable callees, straight-line callers, eligible resource-free record owners, and direct effect-free
argument lists. Borrowed arguments preserve identity and may update typed scalar, record and array
fields; ordinary value arguments retain snapshot semantics. External IR must
carry matching PARAM/ARG and schema descriptors and pass an independent proof.
Borrow IR is native-only; hosted emission rejects it. Receiver methods use
package-qualified record identities and the explicit first-parameter borrow
ABI. Borrowed returns, repeated exclusive aliases, and unproved lifetimes remain
rejected. Ordinary callers still require straight-line owner provenance;
borrowed callees may reborrow only their own root parameters. Arguments stay
effect-free, and external IR cannot overlap a pending exclusive argument with
a nested call.
`native_record_borrow_check.sh` tests mutation, rejected escapes/aliasing/effects,
forged IR, and the real DFA file using isolated dependency types. That isolated
DFA test is not a full-source Stage1 proof. The loop borrow suite also executes
the real CFG dominator, post-dominator and dominance-frontier functions using
isolated IR dependency types. Their native IR is checked with a definite-type
CFG worklist: every reachable predecessor and loop back edge participates in
the meet; called value functions are checked transitively. Unsupported resource
or reference operations remain errors, including unreachable reference escapes.
`native_record_import_check.sh` executes imported record construction, nested
schema defaults, function returns, array constructors and record borrows. It
checks file-local aliases in both source orders and rejects ambiguous imports
and resource-bearing array elements before replacing IR output. Ordinary
string values are not treated as type references.
`native_record_receiver_check.sh` executes mutation through methods, cross-package
same-named methods, the seventh ABI parameter, looping reborrows and recursive
calls. It rejects handle copies/returns, value-parameter escapes, effectful
borrow arguments, duplicate roots, altered schema targets and pending-call
overlap before output replacement or assembler/linker invocation.
`native_syntax_lexer_check.sh` executes the real syntax lexer with its production
types: owned construction, rope source, token codes and positions, returned
array snapshots, and 1030 tokens. Constructor-result ownership requires actual
argument and transitive body/return proof; all callers in an owner-consuming
chain are checked, using the same symbol resolution as native emission. The
standalone borrowing entrypoint has no language parameters and uses host_args()
for environment arguments. Forged fields, ordinary argument types, qualified
call aliases and entry parameters are rejected before native tools or output
replacement. Native append preserves its source, item and length across allocation.
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
It rejects unsupported declarations and syntax before replacing the output.
Function parameters must be parsed and retained; skipping signatures or source
declarations does not implement those language features.

The full 253-file production closure is currently rejected before native IR
output at `ir/middlend_ir_builder.s` (`ir_builder_build`) because its AST graph and borrowed
body operations are not supported by the proof. The AST pointer graph still needs
verified provenance and a supported ownership model.
The native frontend, MIR/SSA lowering and instruction selection also need
strings, arrays, records and control flow before S can compile its own source.
Disabling ownership/schema validation or emitting an inspectable ELF does not
satisfy this requirement. Stage2 and Stage3 have not been demonstrated.

The seed's native runtime now provides private temporary directories, argv and
environment propagation, PATH lookup, exit/signal status, and rope-aware file
paths. File identity checks compare device/inode and detect hard-link and
symbolic-link aliases before output replacement. `native_host_tools_check.sh` executes a native S program which invokes
`as` and `ld`, installs and runs a static ELF, and verifies that cleanup preserves
the destination parent. This checks the build-tool boundary independently of
the unsupported compiler source. Source reads reject embedded NUL and files
larger than the current 16 MiB buffer instead of accepting a truncated prefix.

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

The current full-source frontier is reproduced by
`make selfhost-native-stage1-check`. After source eligibility is implemented,
this gate must build and verify native stage1, emit and run a native assembly
artifact while preserving the destination parent, then compile and execute a
small S program. Passing ELF inspection alone is not execution proof.

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
