#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SRC="$ROOT/src/runtime/process_runner.c"
MAIN_SRC="$ROOT/src/runtime/process_runner_main.c"
OUT_LIB="${1:-$ROOT/src/runtime/libprocess_runner.so}"
OUT_BIN="${2:-$ROOT/src/runtime/process_runner}"

gcc -shared -fPIC -O2 -o "$OUT_LIB" "$SRC"
gcc -O2 -o "$OUT_BIN" "$MAIN_SRC" "$SRC"
echo "built process runner library: $OUT_LIB"
echo "built process runner executable: $OUT_BIN"
