#!/usr/bin/env bash
set -euo pipefail

ROOT="/app/s"
OUT="${1:-$ROOT/runtime/s_native}"

cc -O2 -std=c11 "$ROOT/runtime/s_native_runner.c" -o "$OUT"
echo "built native runner: $OUT"
