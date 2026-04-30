#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
S_BIN="${S_BIN:-$ROOT_DIR/bin/s}"
BASELINE_FILE="${BASELINE_FILE:-$ROOT_DIR/doc/perf_baseline.env}"
MAX_SLOWDOWN_RATIO="${MAX_SLOWDOWN_RATIO:-1.30}"

if [[ ! -x "$S_BIN" ]]; then
  echo "error: s binary not executable: $S_BIN" >&2
  exit 1
fi

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "error: baseline file not found: $BASELINE_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$BASELINE_FILE"

workdir="$(mktemp -d /tmp/s_perf_gate.XXXXXX)"
trap 'rm -rf "$workdir"' EXIT

cat >"$workdir/main.s" <<'EOF'
package main

func main() {
    println("hello, world")
}
EOF

measure_ms() {
  local label="$1"
  shift
  local start end
  start=$(date +%s%N)
  "$@" >/dev/null 2>&1
  end=$(date +%s%N)
  echo "$label $(( (end - start) / 1000000 ))"
}

check_line=$(measure_ms check "$S_BIN" check "$workdir/main.s")
run_line=$(measure_ms run "$S_BIN" run "$workdir/main.s")

echo "$check_line"
echo "$run_line"

check_ms=$(echo "$check_line" | awk '{print $2}')
run_ms=$(echo "$run_line" | awk '{print $2}')

check_limit=$(awk -v b="$CHECK_MS_BASELINE" -v r="$MAX_SLOWDOWN_RATIO" 'BEGIN { printf "%d", (b*r)+0.5 }')
run_limit=$(awk -v b="$RUN_MS_BASELINE" -v r="$MAX_SLOWDOWN_RATIO" 'BEGIN { printf "%d", (b*r)+0.5 }')

echo "limits: check<=${check_limit}ms run<=${run_limit}ms"

if (( check_ms > check_limit )); then
  echo "perf gate fail: check ${check_ms}ms exceeds ${check_limit}ms" >&2
  exit 1
fi
if (( run_ms > run_limit )); then
  echo "perf gate fail: run ${run_ms}ms exceeds ${run_limit}ms" >&2
  exit 1
fi

echo "perf gate: PASS"
