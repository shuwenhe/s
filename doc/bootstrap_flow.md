# Bootstrap Flow

Version: Draft 0.1

This document describes the current bootstrap path used by the repository scripts.

## 1. Goal

The goal is to produce a stage1 compiler first, then use that stage1 compiler to
build the native runner, and finally use that runner for the next self-hosted
steps.

The flow is intentionally fail-fast:

- no script silently falls back to an older compiler when stage1 is expected
- no runtime self-host selection is done unless the caller enables it explicitly
- missing artifacts stop the flow immediately

## 2. Environment Variables

- `S_DISABLE_SELFHOSTED=1`: disable self-host runner delegation in the hosted Python compiler
- `S_ENABLE_SELFHOSTED=1`: allow hosted Python compiler delegation to a self-host runner
- `S_SELFHOSTED_RUNNER=/path/to/s-selfhosted`: explicit runner path when self-host delegation is enabled
- `S_COMPILER=/path/to/stage1`: compiler binary used by the runner build step

## 3. Script Sequence

### Step 1: Resolve dependencies

`misc/scripts/full_nopy_bootstrap.sh` runs `misc/tools/s_resolver` against:

- `src/cmd/compile/main.s`

This produces the dependency list used for diagnostics only.

### Step 2: Build stage1 compiler

`full_nopy_bootstrap.sh` builds `src/cmd/compile/main.s` with:

- `python3 -m compiler build`
- `S_DISABLE_SELFHOSTED=1`

The output is written to:

- `/home/shuwen/tmp/s_compiler_stage1`

If the file is not produced, bootstrap stops.

### Step 3: Build the final native runner

`full_nopy_bootstrap.sh` exports:

- `S_COMPILER=/home/shuwen/tmp/s_compiler_stage1`

Then it calls:

- `misc/scripts/install_selfhost_compiler_launcher.sh`

That script performs two actions:

1. build the self-host launcher from `src/runtime/s_selfhost_compiler_bootstrap.c`
2. build `bin/s-native` through `misc/scripts/build_native_runner.sh`

`build_native_runner.sh` now accepts only the stage1 compiler path through
`S_COMPILER` and invokes:

- `S_DISABLE_SELFHOSTED=1 "$S_COMPILER" build src/runtime/runner.s -o <out>`

There is no Python fallback in this step.

## 4. Expected Output

After the flow completes, the key artifacts are:

- `/home/shuwen/tmp/s_compiler_stage1`
- `/home/shuwen/tmp/s_final_compiler`
- `/home/shuwen/s/bin/s-native`
- `/home/shuwen/s/bin/s-selfhosted`

## 5. Related Files

- [full_nopy_bootstrap.sh](/app/s/misc/scripts/full_nopy_bootstrap.sh)
- [install_selfhost_compiler_launcher.sh](/app/s/misc/scripts/install_selfhost_compiler_launcher.sh)
- [build_native_runner.sh](/app/s/misc/scripts/build_native_runner.sh)
- [hosted_compiler.py](/app/s/src/compiler/hosted_compiler.py)
