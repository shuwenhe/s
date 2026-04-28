#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
STAMP="$(TZ=Asia/Shanghai date +%Y%m%d%H%M%S)"
OUT="$BIN_DIR/s_arm64_${STAMP}"

mkdir -p "$BIN_DIR"

cd "$ROOT_DIR"
gcc -std=c11 -Wall -Wextra -Werror \
  -o "$OUT" \
  src/cmd/compile/seed/s_seed.c \
  src/cmd/compile/seed/bootstrap/bootstrap.c \
  src/cmd/compile/seed/lexical/lexer.c \
  src/cmd/compile/seed/error/error.c \
  src/cmd/compile/seed/syntax/parser.c \
  src/cmd/compile/seed/semantic/analyzer.c \
  src/cmd/compile/seed/intermediate/ir.c \
  src/cmd/compile/seed/code/generator.c \
  src/cmd/compile/seed/runtime/runtime.c

chmod +x "$OUT"

echo "$OUT"
