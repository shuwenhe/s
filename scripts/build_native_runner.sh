#!/usr/bin/env bash
set -euo pipefail

ROOT="/app/s"
OUT="${1:-$ROOT/runtime/s_native}"

# Current bootstrap note:
# - runtime/s_native_runner.s is the S-native source of this MVP runner
# - runtime/s_native_runner.c remains the executable bootstrap used to build it today

cc -O2 -std=c11 "$ROOT/runtime/s_native_runner.c" -o "$OUT"
echo "built native runner: $OUT"
