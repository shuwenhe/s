#!/usr/bin/env bash
set -euo pipefail

ROOT="/app/s"
OUT="${1:-$ROOT/bin/s-selfhosted}"
SRC="$ROOT/src/runtime/s_selfhost_compiler_bootstrap.c"

cc -O2 -std=c11 "$SRC" -o "$OUT"
echo "installed selfhost bootstrap launcher: $OUT"
