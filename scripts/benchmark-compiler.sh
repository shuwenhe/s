#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -x ./bin/s-native ]]; then
  echo "missing ./bin/s-native" >&2
  exit 1
fi

TARGETS=(
  src/cmd/compile/internal/ssa_core.s
  src/cmd/compile/internal/backend_elf64.s
  src/cmd/compile/internal/semantic.s
)

run_bench() {
  local file="$1"
  local rounds="${2:-5}"
  local i
  local total_ns=0

  for ((i=0; i<rounds; i++)); do
    local start end elapsed
    start="$(date +%s%N)"
    ./bin/s-native check "$file" >/dev/null
    end="$(date +%s%N)"
    elapsed=$((end - start))
    total_ns=$((total_ns + elapsed))
  done

  local avg_ns=$((total_ns / rounds))
  echo "$file avg_ns=$avg_ns rounds=$rounds"
}

for t in "${TARGETS[@]}"; do
  run_bench "$t" 5
done
