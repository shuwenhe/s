#!/usr/bin/env bash
set -euo pipefail

ROOT="/app/s"
OUT="${1:-$ROOT/runtime/s_native}"

# Bootstrap-native chain:
# - copy the checked-in launcher template
# - the resulting executable loads runtime/runner.s at runtime

cp "$ROOT/runtime/runner_launcher.py" "$OUT"
chmod +x "$OUT"
echo "built native runner launcher: $OUT"
