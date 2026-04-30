#!/usr/bin/env bash
set -euo pipefail

# S language mainline smoke test: from source to running binary
# Usage: ./scripts/mainline_smoketest.sh

SRC="misc/examples/s/hello.s"
OUT="/tmp/s_hello"
EXPECTED="hello, world"

if ! command -v s >/dev/null 2>&1; then
  echo "error: 's' compiler not found in PATH" >&2
  exit 1
fi

s build "$SRC" -o "$OUT"
"$OUT" > "$OUT.out"
if grep -q "$EXPECTED" "$OUT.out"; then
  echo "mainline smoke test passed"
else
  echo "mainline smoke test FAILED: expected '$EXPECTED' in output" >&2
  cat "$OUT.out"
  exit 1
fi
