# Clean-Room Acceptance — Manifest & Verification Matrix

Deliverable companion to `cleanroom-acceptance-20261103.md`.

## A. Frozen revision

- **Revision:** `0418d05c7967b4850320c2ba5389189d2cecc82f` (`0418d05c7`)
- **Source closure:** exactly **268** unique tracked `.s` files
  (controller aborts if not exactly 268).
- **Mode:** `full` (C Seed → Stage1 → Stage2 → Stage3 + convergence + production).

## B. Host tool manifest (19 tools)

Required and asserted by `misc/scripts/ci-core.sh` before the controller runs,
and installed via `apt-get` (incl. `ripgrep`):

```
git gcc make as ld strace time bash python3 rg
nm objdump readelf sha256sum cmp awk sed grep file timeout strings
```

`rg` (ripgrep) is **mandatory**: the production regression suite invokes it 85+
times; the controller raises `required production dependency missing: rg
(ripgrep)` otherwise.

## C. Verification matrix

| # | Check | Mechanism | Result |
|---|-------|-----------|--------|
| 1 | Exact detached revision | `git clone --no-local --no-checkout` + `git archive <sha>` | PASS |
| 2 | Read-only source inputs | chmod minus write bits on tracked inputs | PASS |
| 3 | No checkpoint/stage reuse | `checkpoint_reuse: false` | PASS |
| 4 | 268-file closure | `source_closure.sh` + exact-count assertion | PASS |
| 5 | C Seed build | `make -B seed-compiler-bin` | PASS |
| 6 | Stage1 from Seed | seed `--compile-native-unit` + `--emit-standalone-amd64` | PASS |
| 7 | Stage2 from Stage1 | stage1 compiles `stage2.sasm`, emits `stage2` | PASS |
| 8 | Stage3 from Stage2 | stage2 compiles `stage3.sasm`, emits `stage3` | PASS |
| 9 | True-selfhost verify | `verify_true_selfhost.sh` per stage | PASS |
| 10 | Stage execution | `selfhost-execution.sh` per stage | PASS |
| 11 | Strict type identity | `native_type_identity_check.py` (expects `Unknown[int]`→false, returns 42) | PASS |
| 12 | GC check | `native_gc_check.py` per stage | PASS |
| 13 | GC object check | `native_gc_object_check.py` per stage | PASS |
| 14 | Public MIR oracle | stage1 `--emit` of full compiler `compiler.mir` | PASS |
| 15 | Reachable-function convergence | `labels[2] == labels[3]` (944 funcs) | PASS |
| 16 | Byte-exact assembly convergence | `stage2.sasm` == `stage3.sasm` | PASS |
| 17 | Byte-exact executable convergence | `stage2` == `stage3` | PASS |
| 18 | Stage source manifests identical | closure digests unchanged across stages | PASS |
| 19 | Execve audit | strace on every stage transition (7 logs) | PASS |
| 20 | Production regression | `make selfhost-canonical-production-check` (85 checks) | PASS |
| 21 | Compiler not replaced | post-production digest comparison | PASS |

## D. Deliverables produced

- `cleanroom-acceptance-20261103.md` — acceptance report.
- `acceptance-manifest.md` — this file (manifest + matrix).
- `evidence-index.md` — pointer index to raw evidence.
- `misc/scripts/ci-core.sh` — CI entrypoint (committed).
- `doc/selfhost-verification/selfhost-workflow.yml` — CI workflow, canonical
  preserved copy (the `.github/workflows/selfhost.yml` path is removed by repo
  commit `c8448bcb8` and reverted by the environment; copy this file there to
  enable CI).
- `doc/selfhost-verification/cleanroom.md` — host dependency manifest (prior).
