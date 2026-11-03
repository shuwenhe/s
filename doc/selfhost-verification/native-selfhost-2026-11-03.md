# Native self-hosting verification — 2026-11-03

The compiler source is the recovered `6f0712321ebeb00cbb23114f2b6d22fd4499e645`
snapshot. All 268 compiler closure files match the working checkout byte for
byte. Previous checkout versions are retained in the evidence directory.

Evidence: `.bootstrap/selfhost-20261103/` (generated, not committed).
`source-6f0712321.tar` preserves the complete buildable source snapshot;
`source-manifest.json` records the original tracked file hashes.

## Verified checkpoints

- C seed -> standalone native stage1: retained successful compile and emit
  receipts; stage1 native verification and source-dependent execution rerun.
- Stage1 -> stage2: retained successful full 268-file compile receipt (exit 0,
  2562.51 seconds). Native assembly contains 944 reachable function labels;
  the canonical trace lowers 2570 unique MIR functions. The old supervisor's
  requirement for 2568 native labels was incorrect because emission prunes
  unreachable functions. Neither emission nor validation was bypassed.
- Fresh stage2 -> stage3 compilation completed with exit 0 in 1212.82 seconds.
  Fresh assembly and the executable linked by stage2 both match stage2 exactly,
  without normalization. Native verification passes on the freshly linked ELF.
  `.complete`, `.accepted` and `ACCEPTED.json` record final acceptance.
- All three stages pass native ELF verification, source-dependent execution,
  strict type identity, GC reclamation/root preservation and native object tests.
- Stage2 and stage3 compile and execute extracted production MIR/SSA/AMD64
  validators. Positive cases pass; undefined values, dominance, phi inputs,
  duplicate/invalid IDs, types, references, CFG edges and ABI calls are rejected.
- The complete `make -o compiler selfhost-canonical-production-check` suite
  passes with the final stage3 compiler installed in the preserved snapshot.
  The compiler hash remains unchanged throughout the suite.
- The installed checkout `bin/s_compiler` is stage3. `bin/s build
  test/native-build/program.s` produces a native executable returning 25 for
  input 7 and 10 for input 2.

## Implementation recovered into the checkout

Balanced source concatenation preserves file-boundary bytes while limiting
intermediate storage. Native allocation uses a non-moving conservative GC with
stack, register and global roots, with C-object lifetime handling. MIR and SSA
dominance computation uses indexed CFG edges and avoids repeatedly copying
instruction payloads. Strict type validation remains enabled. The semantic
prelude qualification needed by the complete source closure is preserved.
The checked-in GC assembly and S emitter reproduce exactly from their runtime
sources (`python3 misc/scripts/regenerate-native-gc.py --check`).

## Reproduce

From the checkout, run `make selfhost` for the full seed -> stage1 -> stage2 ->
stage3 bootstrap and exact assembly/ELF comparison. Run
`make -o compiler selfhost-canonical-production-check` to exercise the installed
compiler without replacing it. Linux/amd64 and the native assembler/linker are
required. Full compiler builds take tens of minutes.

## Converged artifact hashes

- Assembly SHA-256: `3b2cd81a98d4935783708833e35c1254cceda2cb2f1666e8faae9c584b572045`
- Executable SHA-256: `83baacc7bb370141844d71029b9345a81c08c095197ddb1752dfead49fa896ce`

The successful Seed -> stage1 and stage1 -> stage2 checkpoints were recovered
rather than recomputed in this session. Both were freshly re-linked and compared
byte for byte; the stage2 -> stage3 full-source compilation was run anew.
