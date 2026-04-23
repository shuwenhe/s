#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -x ./bin/s-native ]]; then
  echo "missing ./bin/s-native" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

for i in $(seq 1 50); do
  file="$TMPDIR/fuzz_${i}.s"
  cat >"$file" <<EOF
package fuzz
func main() int32 {
    var x = $((RANDOM % 100))
    var y = $((RANDOM % 100))
    if x < y {
        x
    } else {
        y
    }
}
EOF
  ./bin/s-native check "$file" >/dev/null || {
    echo "fuzz failure at iteration $i" >&2
    exit 1
  }
done

echo "fuzz-check: ok"
