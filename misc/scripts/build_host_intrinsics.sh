#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SRC="$ROOT/src/runtime/host_intrinsics.c"
OUT="${1:-$ROOT/src/runtime/libhost_intrinsics.so}"

mkdir -p "$(dirname "$OUT")"

cc -shared -fPIC -O2 -std=c11 "$SRC" -o "$OUT"
echo "built: $OUT"
