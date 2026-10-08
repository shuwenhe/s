# S Native Self-Hosting Baseline

Date: 2026-10-08

## Status

```yaml
seed -> stage1:           PASS
stage1 -> stage2:         PASS
stage2 -> stage3:         PASS

assembly convergence:     PASS
binary convergence:       PASS

original OOM:             FIXED
stage2 peak RSS:          64,464 KB
stage2 peak VMS:          80,760 KB
runtime modifications:    NONE

native self-host core:    PROVEN
full bootstrap suite:     INCOMPLETE
canonical authority:      NOT PROVEN BY THIS WORK
```

## Evidence

The Stage2 -> Stage3 frontier no longer fails with the Linux OOM killer.
The repaired Stage2 generated Stage3 successfully, and the generated Stage2
and Stage3 assembly and binaries converged.

Final controlled Stage2 -> Stage3 memory diagnostic:

- result: `PASS_STAGE3_GENERATED`
- compile max RSS: `64,464 KB`
- compile max VMS: `80,760 KB`
- Stage3 assembly: present
- Stage3 object: present
- Stage3 binary: present

The original OOM path was previously observed near 13 GiB anonymous RSS.
The post-fix Stage2 -> Stage3 compile peak is approximately 63 MiB RSS.

## Root Cause

The OOM was caused by incorrect native self-host code generation for multiline
string concatenation in the `asm_*` assembly generator path.

The faulty Stage2-generated control flow omitted required continuation work in
assembly generation. In the most visible failure, `asm_literals` did not advance
to the next string literal, so the same literal was processed repeatedly.

That non-terminating code-generation loop produced a flood of 32-byte Rope
allocations. The Rope allocation growth was a symptom of the bad generated
control flow, not a failure of `s_alloc` or the native runtime allocator.

## Scope

This baseline freezes the native self-hosting core status only:

- `seed -> stage1`
- `stage1 -> stage2`
- `stage2 -> stage3`
- Stage2/Stage3 assembly convergence
- Stage2/Stage3 binary convergence
- Stage2 -> Stage3 memory behavior

It does not prove the full native bootstrap suite, because the later smoke test
is currently blocked by the missing or unreadable fixture
`test/selfhost/bootstrap_native_selfhost_frontier.s`.

It also does not prove canonical `frontend -> middlend -> backend` authority.
That is a separate proof line and must not be inferred from this native
self-hosting result.

## Next Work

P0: Restore the real smoke fixture
`test/selfhost/bootstrap_native_selfhost_frontier.s`, determine its intended
coverage and history, and rerun the complete `native-bootstrap.sh` suite. Do not
skip the smoke test to obtain a PASS.

P1: Add regression coverage for multiline expression/code-generation behavior.
The regression should verify Stage1 and Stage2 generated code, not just parser
acceptance. It should cover multiline `return`, assignment continuation, and
assembly snippets containing generated jump labels.

## P0 Completion Update

The historical smoke fixtures were restored from Git history:

- `test/selfhost/bootstrap_native_selfhost_frontier.s`
- `test/selfhost/bootstrap_native_rope.s`

The frontier fixture covers `else if`, local assignment, negative integer
classification, and six-argument native calls. The rope fixture covers string
concatenation, `len`, `__host_char_at`, and string equality.

After restoring those fixtures, the complete native bootstrap suite was rerun:

```yaml
full bootstrap suite:     PASS
native-bootstrap result:  NATIVE BOOTSTRAP COMPLETE
workdir:                  .bootstrap/full-native-bootstrap-p0
```

Observed complete-suite results:

- `seed -> stage1`: PASS
- `stage1 -> stage2`: PASS
- `stage2 -> stage3`: PASS
- assembly convergence: PASS
- binary convergence: PASS
- seed dependency audit: PASS
- stage2 compiler smoke test: PASS
- conformance: PASS

This P0 update extends the native bootstrap status from core-proven to full
native bootstrap suite PASS. It still does not prove canonical
`frontend -> middlend -> backend` authority.
