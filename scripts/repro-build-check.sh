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

SRC="$TMPDIR/repro_sample.s"
OUT1="$TMPDIR/out1.bin"
OUT2="$TMPDIR/out2.bin"

cat >"$SRC" <<'EOF'
package main
func main() int32 {
    0
}
EOF

./bin/s-native build "$SRC" -o "$OUT1" >/dev/null
./bin/s-native build "$SRC" -o "$OUT2" >/dev/null

cmp -s "$OUT1.export" "$OUT2.export"
cmp -s "$OUT1.abi" "$OUT2.abi"

printf 'repro-build-check: ok\n'
