# Reproducible native self-host acceptance

Use Linux/amd64, a clean committed checkout and a completely new output path.
All work is committed on `main`; acceptance uses separate detached checkouts.

```sh
FROZEN_COMMIT=$(git rev-parse HEAD)
bash misc/scripts/ci-core.sh "$FROZEN_COMMIT" /tmp/s-core-new core
bash misc/scripts/ci-core.sh "$FROZEN_COMMIT" /tmp/s-full-new full
```

Install dependencies before running: Git, build-essential (GCC and cc), binutils,
Python3, python3-yaml, Bash, ripgrep, strace, GNU time, file, coreutils, findutils
and tar. System tools are preflighted before compilation. `rg` may live outside
`/usr/bin`: the controller locates it, pins a copy in the new run's `host-tools`,
records its original path and SHA-256, and exposes only that directory plus
`/usr/bin:/bin`. Missing ripgrep is an explicit early failure; no grep fallback
or skipped regression is permitted. Unit tests exercise both presence and absence.
Tracing needs permission to trace only the run's own newly created child processes.

## Fresh build contract

There is no resume option. Existing output directories, command receipts and
compiler outputs are refused. Fix a failure, commit it, and start in a new
output directory. Prior failed attempts remain intact and never become accepted
by rerunning only their final failed check.

The controller independently clones the exact commit without hardlinks or object
alternates, verifies checkout bytes against committed Git blobs, disables inherited
Git overrides/attributes/hooks and makes tracked input files read-only. Its own
source hash must match the frozen controller. Ordered production closure discovery
must yield exactly268 unique tracked S files. All tracked source hashes and every
stage's closure hashes are checked throughout the build.

Full mode builds a new C Seed using the committed makefile, then:

1. Seed → native Stage1, followed by ELF, source-dependent execution, strict type,
   GC and native C-object checks.
2. New Stage1 exports the complete typed, verified public MIR. An independent
   Python graph traversal derives expected reachable functions from entry plus
   reserved `.__global_init_` initializer roots. The prefix rule is tied to the
   frozen `program_environment.s`. It checks call-instruction/table agreement,
   dense native indices, entry, global roots and direct native call edges.
3. New Stage1 → Stage2; new Stage2 → Stage3. Each binary passes the same gates.
4. New Stage3 actually compiles the complete268-file source again and links and
   executes that result. Its assembly and ELF must also converge with Stage3.
5. Stage2/Stage3 assembly and ELF are compared as raw bytes, without normalization.
6. The full production suite runs using the newly built Stage3. GNU make trace
   must show every parser/production test recipe; missing recipes fail acceptance.
   Source manifests and the installed compiler hash are checked again.

Core mode freshly builds C Seed and full-source native Stage1 and runs the full
production suite with it. Stage2, Stage3, selfcompile and convergence remain
explicitly NOT RUN; it writes `CORE-PASSED.json`, never `ACCEPTED.json`.

## Evidence and metrics

`OUTPUT/evidence` contains source.tar, configuration, all-source and ordered
closure SHA-256 manifests, per-stage source manifests, public MIR and expected
function inventory, all new compiler binaries/assembly, exact comparisons,
production test inventory, and a machine-readable acceptance report.

Every command retains separate stdout/stderr, an exec trace at compiler
boundaries, GNU-time metrics, output hashes and a JSON exit receipt. Native
compiler subprocesses may execute only the selected producer, canonical system
assembler/linker and declared mkdir/rm temporary-file helpers. Original C Seed
or another compiler cannot silently service a later stage.

Per-second resource TSV files and heartbeat.json retain actual sampled descendant
RSS, VmData, visible-process CPU counters, processed MIR functions and diagnostic
counts. Minute console heartbeats show healthy work. Sampled live CPU can decrease
when children exit, and main-thread child enumeration can miss children spawned
by other threads; authoritative final CPU totals/utilization and peak RSS come
from GNU time. VmData describes mapped data, not cumulative allocator events.
Function counts describe MIR lowering, not the smaller pruned native inventory.
Test counts describe executed script recipes, not every assertion inside scripts.

A full `ACCEPTED.json` is emitted only after all required gates and immutable
source checks pass. Failed attempts retain `FAILED.json` with FAIL for the actual
phase and NOT RUN for downstream phases. Prior local checkpoints are diagnostic
history, not fresh acceptance evidence.

## GitHub Actions

`.github/workflows/selfhost.yml` checks out exact commits on fresh Ubuntu22.04
runners, installs all dependencies and invokes the same entrypoint. Core runs on
main pushes/PRs. Full runs on explicit dispatch, weekly schedule (Saturday20:17
UTC, Sunday04:17 Asia/Shanghai), or a push marked `[verify-full-bootstrap]`.
Actions are pinned to verified official commits. No compiler cache is restored.

Evidence is always packed as tar.gz to preserve executable modes and uploaded,
including failures. GitHub retention is90 days; local evidence is retained
separately. Source archives replace an uploaded Git checkout; failure temporary
files and command logs remain in the evidence archive. Local PASS and actual
GitHub workflow PASS are reported separately, each against its own exact SHA.

```sh
python3 -m unittest discover -s test/bootstrap-reproducibility -v
```

Policy tests cover fresh cloning, committed bytes, source drift, dependency
preflight, refused reuse, failure statuses, monitoring, independent MIR inventory,
rejected compiler delegation and CI's failure-evidence/trigger configuration.
