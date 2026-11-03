# Clean-room self-hosting

Run on Linux/amd64 with Python 3, Git, GNU make, GCC, binutils, GNU time and
strace. Commit all required inputs first. Choose an output path that does not
exist. The command creates a separate, detached, non-hardlinked checkout of the
exact revision. It never copies the working tree's ignored outputs.

```sh
python3 misc/scripts/cleanroom-selfhost.py \
  --repository . --revision HEAD --output /tmp/s-cleanroom-new-run
```

`--mode full` is the default. It builds C Seed, the complete 268-source native
Stage1, Stage2 using only that Stage1, and Stage3 using only that Stage2. There is
no resume option. Every failed attempt remains in its own directory. Fix and
commit the cause, then use a new output directory.

`--mode core` builds a new C Seed and full-source native Stage1, then runs the
production suite using that Stage1. It leaves Stage2, Stage3 and convergence as
NOT RUN and cannot write full acceptance. This is the faster per-commit CI gate.

The controller sanitizes inherited build/runner/loader settings, pins the target
and source root, and makes tracked source files read-only. Every Git invocation ignores inherited configuration overrides, global attributes
and hooks. Checkout bytes are compared against the selected commit’s Git blobs.
It checks tracked contents, executable bits and Git revision throughout the run. Generated files
live in ignored checkout directories or the evidence tree, never in source files.

Every compiler boundary is traced with strace. Successful exec calls may target
only the selected newly built producer, the native assembler/linker, and the declared
`mkdir`/`rm` temporary-file helpers. This
prevents delegation to another compiler from being mistaken for native bootstrap.
Tracing requires ptrace permission for the controller's own new child processes;
containers which deny it must grant that permission explicitly. The controller
never signals unrelated or existing processes.

## Evidence

`OUTPUT/evidence/` contains:

- `source.tar`: exact committed source archive.
- `configuration.json`: revision, environment, host and build configuration.
- `source-manifest.json` and `.after.json`: all tracked input hashes and modes.
- `sources`, `source.sha256`, `closure-sha256.json`: ordered 268-file closure.
- `stageN-source-sha256.json`: actual source hashes at each stage boundary.
- `logs/`: separate stdout, stderr, GNU-time metrics and JSON command receipts;
  compiler transitions also retain execve traces.
- `build/`: newly built seed, Stage1 IR, all three native compilers and Stage2/3
  assembly. No earlier checkpoint is imported.
- `compiler-source.s`, `compiler.mir`, `oracle-input-sha256.json`: exact joined
  source and public MIR freshly generated using the new Stage1. An independent
  Python graph traversal computes expected entry/global-initializer reachability
  before SSA pruning. The reserved `.__global_init_` root rule is specific to the
  frozen `program_environment.s` implementation.
- `expected-functions.json`, `stageN-functions.json`: original-order reachable
  function inventory, dense native indices, direct-call edges and startup roots.
  Both assembly outputs must match this independent MIR inventory, not merely
  each other. Duplicate/undefined labels and wrong entries also fail.
- `convergence.json`: exact byte comparisons of assembly and ELF outputs.
- `artifact-sha256.json`, `status.json`, `ACCEPTED.json` or `FAILED.json`.

`ACCEPTED.json` is written only after all three stages, their execution/type/GC/
object checks, source manifests, byte convergence and complete production suite
pass. `CORE-PASSED.json` is deliberately a different receipt.

## Controller tests

```sh
python3 -m unittest discover -s test/bootstrap-reproducibility -v
```

These create real temporary Git repositories and subprocesses. They check fresh
checkout isolation, dirty-source rejection, refused output reuse, source drift,
sanitized environments, retained failure logs, missing outputs, byte differences,
function-label errors and rejected delegation. The two exec-trace tests require
permission to trace their newly spawned processes.
