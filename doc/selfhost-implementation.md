# Compiler self-hosting implementation

The requested outcome is a compiler that compiles its own production source,
then repeats that compilation without the C seed. Acceptance is the existing
`make selfhost` protocol: a native stage1 builds stage2, stage2 builds stage3,
and both assembly artifacts and ELF files compare byte for byte. Stage3 must
also compile and run an independent program. The C seed is trusted only for
stage1. Source declarations, ownership checks and rejected constructs must not
be discarded to obtain convergence.

## Existing boundaries

`native-bootstrap-no-manifest.sh` already resolves the production closure and
enforces the artifact protocol. `handle_compile_unit` uses the S-written
frontend, MIR verifier, SSA lowering and amd64 emitter. Its current executable
subset is integer/void straight-line code. The baseline on 2026-10-22 is 252
files; `make selfhost` rejects a misparsed pointer parameter at `ir/dfa.s:28`.

## Implementation sequence

1. Correct ambiguous pointer parameters using actual record declarations,
   preserving both supported parameter orders and imported type identities.
   Run positive native mutation tests and negative ownership tests.
2. Preserve package and import identity through the native frontend. Save
   each function's declaration scope while collecting signatures, restore
   that scope for body parsing, and resolve calls without merging package
   namespaces. Imports are file-local; missing packages and ambiguous aliases
   are errors. The first source package remains the entry package.
3. Extend executable MIR, its verifier, SSA lowering and amd64 emission with
   CFG branches, loops and variable joins. Unsupported control flow must keep
   rejecting until all four boundaries implement it.
4. Add string, array and record value layouts and their runtime ABI, followed
   by extern intrinsics, enums, constants, switches and the remaining source
   constructs required by the production closure. Record borrowing must retain
   the independent source and native-IR proofs.
5. Compile the complete closure into stage1, then execute the unmodified
   stage2/stage3 protocol and independent-program smoke test. Update status
   only from actual artifacts and execution results.

## Current work and checks

- [ ] Pointer parameter regression: add an execution test, observe failure,
  correct declaration-based disambiguation, and run the native record suite.
- [ ] Package scopes: add cross-package native compilation/execution and
  namespace-isolation rejection tests; observe failure, implement scope
  preservation, and run frontend, artifact and native-build checks.
- [ ] Re-run `make selfhost` and record the exact remaining failure.

Package-scope review must cover same-named functions in different packages,
same alias bound differently in two files of one package, local variables
shadowing imports, absent imported packages, and preservation of prior output
after rejection. These changes do not establish complete self-hosting by
themselves; the final acceptance above remains required.
