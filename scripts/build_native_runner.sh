#!/usr/bin/env bash
set -euo pipefail

ROOT="/app/s"
OUT="${1:-$ROOT/runtime/s_native}"

# Preferred chain:
# - try to build runtime/s_native_runner.s through the hosted S compiler first
# - fall back to runtime/s_native_runner.c while the S-native runner still uses
#   language/runtime features that the hosted compiler backend cannot lower yet

if command -v python3 >/dev/null 2>&1; then
    if (cd "$ROOT" && python3 -m compiler build "$ROOT/runtime/s_native_runner.s" -o "$OUT"); then
        echo "built native runner through hosted S build path: $OUT"
        exit 0
    fi
    echo "S-native runner build unavailable, falling back to C bootstrap" >&2
fi

cc -O2 -std=c11 "$ROOT/runtime/s_native_runner.c" -o "$OUT"
echo "built native runner from C bootstrap: $OUT"
