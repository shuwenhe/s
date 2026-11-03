> Historical evidence for revision `0418d05c7`, retained for provenance. It does not certify the current source, the strengthened type-negative tests, Stage3 full selfcompilation, or GitHub Actions. Current reproduction instructions are in [cleanroom.md](cleanroom.md).

# Clean-Room Acceptance — Evidence Index

All raw evidence lives under:

```
/tmp/cleanroom-acceptance-0418d05c7/evidence/
```

Produced by `misc/scripts/cleanroom-selfhost.py --mode full` against revision
`0418d05c7967b4850320c2ba5389189d2cecc82f`.

## Primary verdict files

| Path | Meaning |
|------|---------|
| `evidence/ACCEPTED.json` | Overall acceptance = PASS (full mode) |
| `evidence/status.json` | Per-stage status map (all PASS) |
| `evidence/FAILED.json` | **Absent** (would indicate failure) |

## Per-phase results & logs

Directory `evidence/logs/`:

- `results.json` — machine-readable record of every phase (command, exit,
  expected exit, SHA256 of outputs, RSS, wall time).
- `active.json` — last active phase (informational; run complete).
- `seed-build.*`, `stage1-*.*`, `stage2-*.*`, `stage3-*.*`, `production.*` —
  per-phase `stdout.log` / `stderr.log` / `time` (GNU `/usr/bin/time -v`).
- `*.execve.log` — `strace -f -e trace=execve` audit for each stage
  transition: `stage1-compile`, `stage1-emit`, `stage1-public-mir`,
  `stage2-compile`, `stage2-emit`, `stage3-compile`, `stage3-emit`.

## Convergence & artifacts

| Path | Meaning |
|------|---------|
| `evidence/convergence.json` | byte-exact convergence record (assembly + executable SHA256, 944 funcs) |
| `evidence/artifact-sha256.json` | final bootstrap artifact digests |
| `evidence/closure-sha256.json` | per-file closure digests |
| `evidence/source.sha256` | flat `sha256  path` closure listing |
| `evidence/source.tar` | `git archive` of the frozen revision (SHA in `results.json`) |
| `evidence/sources` | the 268-file source closure list |
| `evidence/compiler.mir` | public-MIR oracle emitted by Stage1 |
| `evidence/expected-functions.json` | reachable-function oracle (Stage2/Stage3 must match) |

## Configuration & manifests

| Path | Meaning |
|------|---------|
| `evidence/configuration.json` | frozen clone + environment + audit settings |
| `evidence/source-manifest.json` | input file manifest (pre-build) |
| `evidence/source-manifest.after.json` | input file manifest (post-build, must match) |
| `evidence/host-tools/` | host-tool manifest produced by the controller |

## Build artifacts (binaries)

Directory `evidence/build/`:

- `seed` — C Seed reference compiler.
- `stage1.ir`, `stage1` — Stage1 IR and executable.
- `stage2.sasm`, `stage2` — Stage2 assembly and executable.
- `stage3.sasm`, `stage3` — Stage3 assembly and executable (byte-identical to Stage2).

## Reproduce

```sh
python3 misc/scripts/cleanroom-selfhost.py \
  --repository /app/shuwen/s \
  --revision 0418d05c7967b4850320c2ba5389189d2cecc82f \
  --output /tmp/cleanroom-acceptance-0418d05c7 \
  --mode full
```

Or via CI:

```sh
sudo ./misc/scripts/ci-core.sh 0418d05c7967b4850320c2ba5389189d2cecc82f /tmp/cleanroom-ci
```
