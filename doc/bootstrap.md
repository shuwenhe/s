# S compiler bootstrap and production roadmap

## Current, verified state

The checked-in compiler is **not yet a complete production compiler** and is
**not yet independently bootstrapped from S source**.  This distinction is
important:

* `make native-bootstrap` builds the trusted C seed (`bin/s_seed`), uses it to
  construct `stage1`, then has the resulting S compiler emit assembly for
  `stage2` and `stage3`.  The two later stages must converge byte-for-byte.
* The installed `bin/s` is a static Linux/amd64 ELF with no C-seed or libc
  dependency. `verify_true_selfhost.sh` checks this artifact property.
* Artifact independence is not provenance independence: stage1 was created by
  the C seed, and `native-bootstrap.sh` invokes the host assembler and linker.
* `make direct-bootstrap` is the actual no-assembler/no-linker gate. It
  currently fails because `src/cmd/compile/selfhost/compiler.s` is outside the
  direct native-code generation subset. Do not describe that target as passing
  until it builds stage2 and stage3 and they compare equal.
* `selfhost-nostdlib` is deliberately a failing placeholder when
  `bin/s_nostdlib` is absent; it is not evidence of a no-C build.

The C seed remains a legitimate, small *initial trust root*, just as Go uses a
previous Go release to bootstrap.  “Pure S self-hosting” starts only after a
reviewed S compiler binary can reproduce itself directly; eliminating every
non-S program in the initial creation of that first binary is a separate
bootstrapping project (hex seed/assembler/linker or a supplied trusted binary).

## What the Go compiler actually does

Go's `cmd/compile` is one component of a toolchain, not a single parser that
writes an executable. Its essential pipeline is:

```
packages + export data
  -> syntax/parser -> typed IR -> type checking and generic instantiation
  -> escape analysis / inlining / lowering / walk
  -> SSA construction -> target-independent SSA optimization
  -> target rewrite / register allocation / object writer
  -> linker + runtime + DWARF + build cache
```

The source directories in `go/src/cmd/compile/internal` are useful design
references, but copying their names or changing the extension to `.s` does not
implement the contracts between them.  Go relies on the surrounding `cmd/go`,
`cmd/link`, `internal/abi`, runtime, export-data format, and a large,
continuously-run conformance suite.

## Gap assessment for this repository

| Area | Present here | Required before a production claim |
| --- | --- | --- |
| Bootstrap | C seed -> static S stage2/stage3 assembly convergence | Direct S->ELF stage2->stage3 convergence; reproducible provenance and signed stage0 policy |
| Front end | A bootstrap-subset parser/compiler and lexer compatibility checks | One complete grammar, recovery diagnostics, modules/import graph, name resolution, full type system and semantic conformance |
| Middle end | Files named for IR/SSA passes and a small bootstrap compiler | A single executable typed IR/SSA pipeline with verifier after each phase and differential tests |
| Backend | Linux/amd64 direct ELF slices; assembly emission | Object format, relocations, ABI classification, register allocation, stack maps, GC barriers, DWARF, linker integration, more targets |
| Runtime | Small no-libc amd64 runtime probe | Allocator/GC (or specified ownership runtime), panic/unwind, scheduler/threads, FFI and stable ABI |
| Tooling | Make targets and focused smoke tests | Package build driver, dependency/cache model, formatter, language server hooks, cross compilation and reproducible builds |
| Quality/security | Byte comparison and a few positive/negative cases | Unit/integration/fuzz/regression suites, corpus tests, sanitizer/UB checks for stage0, deterministic releases and supply-chain attestations |

## Implementation order and acceptance gates

Work in this order; do not add architecture or optimization targets before the
previous gate is green.

1. **Freeze the bootstrap language subset.** Keep `compiler.s` in a documented
   subset and add a test that rejects every unsupported construct with a source
   position. This keeps stage1 auditable.
2. **Finish direct ELF output for that subset.** Replace the
   `source is outside implemented native slices` rejection with complete
   compilation of `compiler.s`: ELF writer, sections, symbols, relocations,
   string/data layout, calls, stack arguments, and syscalls. Gate: `make
   direct-bootstrap` produces equal stage2/stage3 binaries without `as` or
   `ld`.
3. **Make the bootstrap runtime S-owned.** Move all compiler-required I/O,
   allocation, argument and error facilities behind documented S runtime APIs;
   keep the Linux/amd64 syscall assembly as a separately audited target shim.
   Gate: no compiler artifact references seed, libc, host forwarding, assembler
   or linker paths; source closure is recorded.
4. **Build one real front end.** Define language specification and compatibility
   tests first, then implement parser, typed AST, resolver, type checker and
   package/import export data. Remove duplicate/demo paths rather than keeping
   parallel pseudo-pipelines.
5. **Build and verify SSA.** Use explicit IR invariants, dominators, CFG
   validation, canonical lowering, escape analysis, inlining and only then
   optimizations. Every optimization needs semantic/differential tests.
6. **Production backend and runtime.** Start with a complete Linux/amd64 ABI
   and object/linker contract, stack maps and debug info; only then add arm64
   and other architectures from the same tested IR contract.
7. **Release gate.** Require clean-tree bootstrap, direct stage2==stage3 byte
   equality, compiler self-build of standard library and test corpus, fuzz and
   negative diagnostics, reproducible build in two environments, and an
   artifact/SBOM/provenance audit.

## Commands and honest interpretation

* `make native-bootstrap` — valuable intermediate convergence gate; **uses C
  seed and host `as`/`ld`**.
* `make true-selfhost-check` — confirms the installed ELF has no discovered
  C-seed/libc linkage; **does not prove source provenance**.
* `make direct-bootstrap` — required direct-machine-code self-host gate;
  **currently expected to fail** until step 2 is implemented.
* `make selfhost-nostdlib` — experimental placeholder; it is green only when a
  real `bin/s_nostdlib` is built by the preceding gates.
