#!/usr/bin/env bash
set -euo pipefail

ROOT="/app/s"
SELFHOST_OUT="${1:-$ROOT/bin/s-selfhosted}"
NATIVE_OUT="$ROOT/bin/s-native"
SRC="$ROOT/src/runtime/s_selfhost_compiler_bootstrap.c"

"$ROOT/misc/scripts/build_native_runner.sh" "$NATIVE_OUT"
cc -O2 -std=c11 "$SRC" -o "$SELFHOST_OUT"
echo "installed selfhost compiler launcher: $SELFHOST_OUT"
echo "installed native runner: $NATIVE_OUT"
