# Native selfhost memory

The seed builds Stage1; Stage1 compiles the full source closure into Stage2.
Avoid interpreting a memory regression passing as Stage2/Stage3 convergence.

## Allocation fixes (2026-10-27)

- File reads previously retained a 16 MiB heap allocation per input. The runtime
  now uses a temporary mapping and retains only actual bytes. Success and error
  paths unmap the buffer; EOF, file-size and source NUL checks remain enforced.
- Loop evacuation previously rooted every local slot, keeping dead AST snapshots.
  Backward CFG liveness now selects roots at the backedge target, including uses
  after branches and loop exits. Dead slots reset to tagged zero. Borrow/global
  eligibility restrictions remain in place.
- Scratch growth releases the old mapping before allocating a replacement.
  Scratch cannot escape: the second evacuation scan restores the live graph to
  the heap before returning.

## Verification

`make selfhost-native-memory-check` includes:

- 264 source reads and rejected reads under 64 MiB address space.
- 128 MiB of dead loop values under 64 MiB, preserving a branch/exit value.
- Growing loop allocations of 8/16/24/32 MiB under 80 MiB.
- A supported 264-file native compile/link under 128 MiB, executing 42.
- Existing snapshot, local-variable, nested-value, borrow/global and rope checks.

The three allocation regressions were observed failing before their fixes.
RSS is resident memory; address-space limits also include reserved mappings.

## Remaining bootstrap boundary

The full 264-file compiler closure failed with `native record allocation failed`
under a 1.5 GiB address-space limit before root liveness was added. With the reader
and liveness/scratch fixes, Stage1 runs under a 512 MiB address-space limit and
reaches a parser rejection at about 241 MiB sampled peak RSS:
`expected '{', found ':='` at concatenated line 17786. The parser does not accept
the C-style `for` initializer in `src/cmd/compile/internal/ir/middlend_cfg.s:47`.

This independent syntax blocker means full selfhost remains incomplete. An
existing `native_unit_pipeline_check.sh` failure (`e3100: semantic check rejected
item`) was also reproduced before the liveness changes.
