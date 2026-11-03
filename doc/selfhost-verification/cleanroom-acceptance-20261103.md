> Historical evidence for revision `0418d05c7`, retained for provenance. It does not certify the current source, the strengthened type-negative tests, Stage3 full selfcompilation, or GitHub Actions. Current reproduction instructions are in [cleanroom.md](cleanroom.md).

# Clean-Room Self-Host Acceptance Report

- **Date:** 2026-11-03
- **Controller:** `misc/scripts/cleanroom-selfhost.py` (`--mode full`)
- **Result:** **ACCEPTED** — `ACCEPTED.json` present, `FAILED.json` absent.
- **Frozen revision:** `0418d05c7967b4850320c2ba5389189d2cecc82f` (short `0418d05c7`)

---

## 1. Summary

The S-language self-hosting compiler was accepted by a **clean-room** build of
the frozen revision. The audited controller built every bootstrap stage fresh
from source — **C Seed → Stage1 → Stage2 → Stage3** — verified **byte-for-byte
convergence**, audited **every stage transition with `execve` tracing**, and ran
the **full canonical production regression**. All checks passed; the production
suite did not replace the accepted compiler.

The decisive fix under test was the MIR builtin-generic reference-element
change: `mir_program_type_supported` now accepts `vec[...]`, `map[...]`,
`set[...]`, `array[...]`, `option[...]`, `result[...]` element types, so that
`&vec[ir.node]` type-checks during the Stage1→Stage2 self-host (previously
reported as `unproven reference parameter`).

## 2. Frozen revision

| Item | Value |
|------|-------|
| Validated revision | `0418d05c7967b4850320c2ba5389189d2cecc82f` |
| Contains | MIR builtin-generic reference-element fix (bootstrap parity) |
| Repo tip at acceptance | `c8448bcb8` (infra/doc delta only; compiler source identical to `0418d05c7`, outside the 268-file source closure) |
| Source closure | exactly **268** unique tracked `.s` files (enforced by controller) |

## 3. Methodology (controller guarantees)

- Detached exact revision via `git clone --no-local --no-hardlinks --no-checkout`,
  then `git archive` of the frozen SHA — no working-tree or branch dependency.
- Tracked source inputs are made read-only; no checkpoint or stage reuse
  (`checkpoint_reuse: false`).
- Host-tool preconditions enforced. **`rg` (ripgrep) is now a hard requirement**
  of the production regression suite (~85+ invocations); the controller fails
  loudly if it is missing (`required production dependency missing: rg`).
- Every bootstrap stage is produced from scratch; stage *N+1* is compiled by
  stage *N*.
- An **`execve` audit** (`strace -f -e trace=execve`) is captured on every stage
  transition: only the freshly built compiler and the trusted host toolchain are
  executed; no prebuilt or external S compiler is ever invoked.
- The production regression must not replace the accepted compiler (a post-run
  digest comparison guards this).

## 4. Stage results — all PASS

| Phase | Status | Note |
|-------|--------|------|
| toolchain | PASS | host toolchain probe |
| source-archive | PASS | `git archive` of frozen SHA |
| source-closure | PASS | 268 unique tracked sources |
| seed-build | PASS | C Seed reference compiler `bin/s_seed` |
| stage1-compile / emit / verify / execution / strict-type / gc / object / public-mir | PASS | Stage1 built by Seed |
| stage2-compile / emit / verify / execution / strict-type / gc / object | PASS | Stage2 built by Stage1 |
| stage3-compile / emit / verify / execution / strict-type / gc / object | PASS | Stage3 built by Stage2 |
| convergence | PASS | byte-exact Stage2 == Stage3 |
| production | PASS | 85 regression checks, no replacement |

## 5. Byte-level convergence — PASS

- Reachable function sets: **stage2 == stage3** (`944` functions).
- `stage2.sasm` SHA256 **==** `stage3.sasm` SHA256 =
  `94cdc72e8327cc0ae4d1da7a0b19648c9f4c23f585693acc11b23546f4217490`.
- `stage2` executable SHA256 **==** `stage3` executable SHA256 =
  `5117540146e62f0ba706b5257a58c9da3f8493503132d8475b5cf917a21d401a`.
- Comparison: **exact bytes, no normalization**.
- Stage source manifests identical to the closure across all stages.

## 6. Production regression — PASS (85 checks)

Representative checks observed passing (no `FAIL` anywhere in the evidence logs):

- `frontend lexer: native module borrow checks, intrinsic slice and character predicates: PASS`
- `canonical native frontend parser preserves AST mutation and error messages: PASS`
- `canonical parser retains enum / public generic structs / control flow / externs / nested record literals / seed operator precedence: PASS`
- `canonical C-style for clauses, optional clauses and malformed headers: PASS`
- `tuple: native tuples, nested aggregate returns, parallel assignment, result status/payload: PASS`
- `source closure inline, grouped, semicolon and aliased imports: PASS`
- `annotation inference work: 222 calls vs 43 initial checking calls; nested execution: PASS`
- `native record collection: 38 lookups for 38 records; cross-package payloads/order 0 and 1: PASS`
- `mir: 6049 appended and 56935 snapshotted elements; diamond, sparse IDs, backedge, unreachable and operand checks: PASS`
- `ssa: 6049 appended and 56861 snapshotted elements; diamond, sparse IDs, backedge, unreachable and operand checks: PASS`

Each canonical check also emitted `true-selfhost verification passed`, confirming
the produced compiler is a genuine self-host.

## 7. SHA256 evidence

| Artifact | SHA256 |
|----------|--------|
| source archive (`source.tar`) | `172eaa3d7f54fad8d22fc9b13f64c4ce8ce1eff1c74a516dbdeb4fce77e33309` |
| source closure (`sources`) | `2fa7e9ca222c0bd90450684d4ef15208ba88e2dfb947483604ac455f1eadde2c` |
| C Seed (`seed` / `bin/s_seed`) | `9a2746e3b662ce46d70f2d62b4aeecd3aba24d1b6262614d518a843bb5c36670` |
| Stage1 IR (`stage1.ir`) | `7f0d74f69eed1a83f61d05f19882142cfb298abdc1833d6bd382a2b6bb861f95` |
| Stage1 executable (`stage1`) | `893140a00e5c195a5e859a081039704202ae07c8200027ea25563e787416ddd0` |
| Public MIR oracle (`compiler.mir`) | `2131209f01c9afa645dab2bdfdfa09f1f52d3c08c79a35ad7dc8e9a8ad218fca` |
| Stage2 assembly (`stage2.sasm`) | `94cdc72e8327cc0ae4d1da7a0b19648c9f4c23f585693acc11b23546f4217490` |
| Stage3 assembly (`stage3.sasm`) | `94cdc72e8327cc0ae4d1da7a0b19648c9f4c23f585693acc11b23546f4217490` |
| Stage2 executable (`stage2`) | `5117540146e62f0ba706b5257a58c9da3f8493503132d8475b5cf917a21d401a` |
| Stage3 executable (`stage3`) | `5117540146e62f0ba706b5257a58c9da3f8493503132d8475b5cf917a21d401a` |

## 8. Execve audit

Seven `execve` audit logs were captured (strace), one per stage transition:
`stage1-compile`, `stage1-emit`, `stage1-public-mir`, `stage2-compile`,
`stage2-emit`, `stage3-compile`, `stage3-emit`. Each confirms only the freshly
built compiler and the trusted host toolchain (`gcc`/`as`/`ld`/`make`/…) were
executed during bootstrap — no prebuilt or out-of-tree S compiler was involved.

## 9. Host tool manifest (19 tools, all verified)

`git gcc make as ld strace time bash python3 rg nm objdump readelf sha256sum
cmp awk sed grep file timeout strings`

`ci-core.sh` installs the exact set via `apt-get` (incl. `ripgrep`) and then
asserts the presence of all 19 before invoking the controller.

## 10. Remaining items / notes

- **Uncommitted work observed (stash):** a separate fix changes
  `mir_program_dominance_matrix` from `int[]` to `int[][]` (avoids an O(n²)
  row-copy on the native value-array ABI), plus `makefile` adds
  `selfhost-protocol-check` sub-checks. This is work-in-progress, **not** part of
  the frozen revision, and **not** required for this acceptance (the `int[]`
  form passed every production check). Recommend committing it as a follow-up and
  re-running the clean-room to extend coverage.
- **CI harness:** `misc/scripts/ci-core.sh` is committed. The GitHub Actions
  workflow is delivered as a **preserved copy**
  `doc/selfhost-verification/selfhost-workflow.yml` (pins `actions/checkout` and
  `actions/upload-artifact` to full commit SHAs and calls `ci-core.sh` with no
  caches). The repository tree's `.github/workflows/selfhost.yml` was removed by
  repo commit `c8448bcb8` ("Remove GitHub Actions workflows") and is reverted by
  the environment when written there, so the `doc/` copy is the canonical
  artifact; copy it to `.github/workflows/selfhost.yml` to (re-)enable CI.
- **ripgrep dependency:** now a hard precondition of both the controller and
  `ci-core.sh`; the earlier missing-`rg` regression is closed.

## 11. Evidence index

See [`evidence-index.md`](./evidence-index.md). Primary evidence tree:
`/tmp/cleanroom-acceptance-0418d05c7/evidence/`.
