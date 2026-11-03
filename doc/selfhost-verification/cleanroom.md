# Clean-Room Self-Host Bootstrap — Dependency Manifest

This document lists every external tool the reproducible self-host acceptance
pipeline (`misc/scripts/cleanroom-selfhost.py`) and the production regression
suite require. The controller fails loudly with a clear diagnostic if any
required tool is missing, rather than silently skipping a check.

## Build and bootstrap host tools

Verified by the controller at `/usr/bin/<name>` before any build starts.

| Tool | Purpose |
|------|---------|
| `git` | Clone the frozen revision; verify committed blobs. |
| `gcc` | Build the C Seed reference compiler. |
| `make` | Drive the seed/stage build targets. |
| `as`  | GNU assembler (native codegen backend). |
| `ld`  | GNU linker (native executable linking). |
| `strace` | Audit `execve` at the compiler boundary. |
| `time` | `/usr/bin/time -v` peak-RSS measurement. |
| `bash` | Bootstrap shell scripts (`source_closure.sh`, checks). |
| `python3` | Controller, diagnostic scripts, oracle checks. |
| `nm`, `objdump`, `readelf` | Symbol/section inspection of artifacts. |
| `sha256sum`, `cmp` | Artifact hashing and byte comparison. |
| `awk`, `sed`, `grep` | Source-closure and diagnostic text processing. |
| `file` | Artifact type sanity. |
| `timeout` | Bound any single command. |
| `strings` | Binary content inspection. |

## Regression-suite tools

| Tool | Purpose |
|------|---------|
| `rg` (ripgrep) | **Required.** The production regression suite invokes `rg -q` directly in `test/native-bootstrap-diagnostic/*.sh` (e.g. `ssa-lower-binding_check.sh`, `canonical_statement_boundary_production_check.sh`, `canonical_tuple_tail_production_check.sh`). 180+ `rg` invocations grep AST dumps and error logs. |

`rg` is pinned into the controller's isolated `host-tools/` directory and its
SHA-256 recorded, but it must be present on the host first. Install with:

```
apt-get install -y ripgrep      # Debian/Ubuntu; provides /usr/bin/rg
# pacman -S ripgrep             # Arch
# dnf install -y ripgrep        # Fedora/RHEL
```

If `rg` is missing the controller raises
`required host tool missing: rg (ripgrep). The production regression suite
invokes ripgrep directly...` — it does **not** silently skip the regression.

## Deterministic environment

The controller builds a deterministic PATH for every stage:
`host-tools:/usr/bin:/bin`, and strip/deny-list bootstrap and compiler
override variables (`S_BOOTSTRAP_RUNNER`, `S_SOURCE_ROOT`, `S_CLOSURE_MODE`,
`LD_PRELOAD`, `CC`, `CFLAGS`, `MAKEFLAGS`, `GIT_CONFIG_*`) so a contaminated
host environment cannot influence the build.

## Missing-dependency behavior (covered by tests)

`test/bootstrap-reproducibility/test_cleanroom.py` pins `rg` into a host-tools
directory and asserts the controller raises a clear error when `rg` is absent
from the inherited PATH. The upfront host-tool loop in `cleanroom-selfhost.py`
reproduces this diagnostic for every required tool, so a clean-room run fails
loudly and early on a missing dependency instead of mid-build.
