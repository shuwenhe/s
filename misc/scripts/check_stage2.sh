#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPDIR="${TMPDIR:-/tmp}"
ENTRY="src/cmd/compile/main.s"
RESOLVER="$ROOT/misc/tools/s_resolver"
S_COMPILER_ENV="${S_COMPILER:-}"

if [ ! -x "$RESOLVER" ]; then
  echo "resolver missing: $RESOLVER" >&2
  exit 1
fi

if [ -z "$S_COMPILER_ENV" ]; then
  for candidate in \
    "$ROOT/bin/s-native" \
    "$ROOT/bin/s" \
    "/home/shuwen/tmp/s_compiler_improved"
  do
    if [ -x "$candidate" ]; then
      S_COMPILER_ENV="$candidate"
      break
    fi
  done
fi

if [ ! -x "$S_COMPILER_ENV" ]; then
  echo "S compiler missing: $S_COMPILER_ENV" >&2
  exit 1
fi

echo "building stage1 with $S_COMPILER_ENV"
"$S_COMPILER_ENV" build "$ROOT/$ENTRY" -o "$TMPDIR/s_compiler_stage1"

if [ ! -x "$TMPDIR/s_compiler_stage1" ]; then
  echo "stage1 not produced" >&2
  exit 1
fi

echo "building stage2 with stage1"
"$TMPDIR/s_compiler_stage1" build "$ROOT/$ENTRY" -o "$TMPDIR/s_compiler_stage2"

if [ ! -x "$TMPDIR/s_compiler_stage2" ]; then
  echo "stage2 not produced" >&2
  exit 1
fi

sum1=$(sha256sum "$TMPDIR/s_compiler_stage1" | awk '{print $1}')
sum2=$(sha256sum "$TMPDIR/s_compiler_stage2" | awk '{print $1}')

echo "stage1: $TMPDIR/s_compiler_stage1 -> $sum1"
echo "stage2: $TMPDIR/s_compiler_stage2 -> $sum2"

if [ "$sum1" = "$sum2" ]; then
  echo "stage2 matches stage1"
  exit 0
else
  echo "stage2 differs from stage1"
  exit 2
fi
