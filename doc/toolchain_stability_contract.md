# Toolchain Stability Contract

This document defines stable behavior for the `s` CLI wrapper in `bin/s`.

## 1. Stable Exit Codes

- `0`: success
- `2`: usage error (invalid command or argument shape)
- `3`: environment/setup error (missing compiler binary)
- `4`: IO/config path error (missing files or directories)
- `10`: compile pipeline error
- `11`: runtime execution error
- `12`: test suite failure
- `13`: lint failure
- `20`: internal wrapper error

## 2. Stable Output Surface

### 2.1 Success lines

- `s env`: `S_ROOT=...` and other `KEY=value` lines
- `s list [path]`: `<package>\t<count>`
- `s check <file>`: `ok: <file>`
- `s build <file> -o <bin>`: `built <file> -> <bin>`
- `s install <file> --to <dir>`: `installed <file> -> <bin>`
- `s vet`: `vet summary: files=<n> failed=<n>`
- `s test`: `test summary: total=<n> passed=<n> failed=<n>`
- `s lint`: `lint summary: files=<n> failed=<n>`
- `s fmt`: `fmt summary: files=<n> changed=<n>`
- `s clean`: `clean summary: removed=<n>`
- `s work init`: `work init: created <path>`
- `s work use`: `work use: updated <path>`

### 2.2 Error lines

All wrapper-level errors start with:
- `error: ...`

This allows scripts and CI to parse errors predictably.

## 3. Cross-Version Consistency Gate

Use:

```bash
./bin/scripts/toolchain_consistency_gate.sh
```

The gate verifies:
- stable exit codes for representative command classes
- stable output prefix and summary formats
- stable env/list/vet/install/work output surfaces

## 4. Performance Regression Gate

Use:

```bash
./bin/scripts/perf_regression_gate.sh
```

The gate verifies `s check` and `s run` latency against baseline thresholds.
Baseline file:
- `doc/perf_baseline.env`

## 5. CI Recommendation

For release candidates, run in order:

```bash
s fmt src
s lint src
s vet src
s test
./bin/scripts/toolchain_consistency_gate.sh
./bin/scripts/perf_regression_gate.sh
```
