#!/usr/bin/env bash
set -euo pipefail

ROOT="/app/s"
OUT="${1:-$ROOT/runtime/s_native}"

# Preferred chain:
# - build runtime/runner.s through the hosted S compiler
# - the resulting executable is a launcher that runs the S-native runner logic

if command -v python3 >/dev/null 2>&1; then
    if (cd "$ROOT" && python3 -m compiler build "$ROOT/runtime/runner.s" -o "$OUT"); then
        echo "built native runner through hosted S build path: $OUT"
        exit 0
    fi
fi
echo "python3 with hosted compiler support is required to build the S-native runner" >&2
exit 1
