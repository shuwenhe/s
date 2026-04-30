#!/usr/bin/env bash
set -euo pipefail

# S language mainline smoke test: source -> check -> ir -> emit-bin
# Usage: ./bin/scripts/mainline_smoketest.sh

SRC="misc/examples/s/hello.s"
OUT_IR="/tmp/s_hello.ir"
OUT_BIN="/tmp/s_compiler_from_hello"

if [[ ! -x ./bin/s ]]; then
  echo "error: './bin/s' command wrapper not found or not executable" >&2
  exit 1
fi

./bin/s check "$SRC"
./bin/s ir "$SRC" -o "$OUT_IR"
./bin/s emit-bin "$OUT_IR" -o "$OUT_BIN"

if [[ -s "$OUT_IR" && -x "$OUT_BIN" ]]; then
  echo "mainline smoke test passed"
else
  echo "mainline smoke test FAILED: missing ir or native artifact" >&2
  exit 1
fi
