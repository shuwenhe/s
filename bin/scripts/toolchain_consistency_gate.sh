#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
S_BIN="${S_BIN:-$ROOT_DIR/bin/s}"

if [[ ! -x "$S_BIN" ]]; then
  echo "error: s binary not executable: $S_BIN" >&2
  exit 1
fi

workdir="$(mktemp -d /tmp/s_consistency.XXXXXX)"
trap 'rm -rf "$workdir"' EXIT

cat >"$workdir/main.s" <<'EOF'
package main

func main() {
  print("hello, world")
}
EOF

run_case() {
  local name="$1"
  shift
  local out="$workdir/${name}.out"
  local err="$workdir/${name}.err"
  set +e
  "$@" >"$out" 2>"$err"
  local code=$?
  set -e
  echo "$name exit=$code"
  echo "stdout: $(head -n 1 "$out" | tr -d '\r')"
  echo "stderr: $(head -n 1 "$err" | tr -d '\r')"
  echo ""
  echo "$code" >"$workdir/${name}.code"
}

run_case help "$S_BIN" --help
run_case env "$S_BIN" env
run_case list "$S_BIN" list "$workdir"
run_case check "$S_BIN" check "$workdir/main.s"
run_case run "$S_BIN" run "$workdir/main.s"
run_case vet "$S_BIN" vet "$workdir/main.s"
run_case install "$S_BIN" install "$workdir/main.s" --to "$workdir/bin"
run_case work_init bash -lc "cd '$workdir' && '$S_BIN' work init ."
run_case work_show bash -lc "cd '$workdir' && '$S_BIN' work show"
run_case usage_err "$S_BIN" build
run_case lint_fail "$S_BIN" lint "$ROOT_DIR/src/cmd/compile/internal/tests/fixtures/sample.s"

# Stable code assertions
[[ "$(cat "$workdir/help.code")" == "0" ]] || { echo "gate fail: help exit code" >&2; exit 1; }
[[ "$(cat "$workdir/env.code")" == "0" ]] || { echo "gate fail: env exit code" >&2; exit 1; }
[[ "$(cat "$workdir/list.code")" == "0" ]] || { echo "gate fail: list exit code" >&2; exit 1; }
[[ "$(cat "$workdir/check.code")" == "0" ]] || { echo "gate fail: check exit code" >&2; exit 1; }
[[ "$(cat "$workdir/run.code")" == "0" ]] || { echo "gate fail: run exit code" >&2; exit 1; }
[[ "$(cat "$workdir/vet.code")" == "0" ]] || { echo "gate fail: vet exit code" >&2; exit 1; }
[[ "$(cat "$workdir/install.code")" == "0" ]] || { echo "gate fail: install exit code" >&2; exit 1; }
[[ "$(cat "$workdir/work_init.code")" == "0" ]] || { echo "gate fail: work init exit code" >&2; exit 1; }
[[ "$(cat "$workdir/work_show.code")" == "0" ]] || { echo "gate fail: work show exit code" >&2; exit 1; }
[[ "$(cat "$workdir/usage_err.code")" == "2" ]] || { echo "gate fail: usage exit code" >&2; exit 1; }
[[ "$(cat "$workdir/lint_fail.code")" == "13" ]] || { echo "gate fail: lint exit code" >&2; exit 1; }

# Stable output surface assertions
rg -n '^S_ROOT=' "$workdir/env.out" >/dev/null || { echo "gate fail: env output format" >&2; exit 1; }
rg -n '^main[[:space:]]+1$' "$workdir/list.out" >/dev/null || { echo "gate fail: list output format" >&2; exit 1; }
rg -n '^ok: ' "$workdir/check.out" >/dev/null || { echo "gate fail: check output format" >&2; exit 1; }
rg -n '^hello, world$' "$workdir/run.out" >/dev/null || { echo "gate fail: run output format" >&2; exit 1; }
rg -n '^vet summary: files=1 failed=0$' "$workdir/vet.out" >/dev/null || { echo "gate fail: vet summary format" >&2; exit 1; }
rg -n '^installed .* -> ' "$workdir/install.out" >/dev/null || { echo "gate fail: install output format" >&2; exit 1; }
rg -n '^work init: created ' "$workdir/work_init.out" >/dev/null || { echo "gate fail: work init output format" >&2; exit 1; }
rg -n '^\[workspace\]$' "$workdir/work_show.out" >/dev/null || { echo "gate fail: work show output format" >&2; exit 1; }
rg -n '^error: usage: s build <input.s> -o <output.bin>$' "$workdir/usage_err.err" >/dev/null || { echo "gate fail: usage error format" >&2; exit 1; }
rg -n '^lint summary: files=1 failed=1$' "$workdir/lint_fail.out" >/dev/null || { echo "gate fail: lint summary format" >&2; exit 1; }

echo "consistency gate: PASS"
