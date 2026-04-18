#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPDIR="/home/shuwen/tmp"
RESOLVER="$ROOT/misc/tools/s_resolver"
S_COMPILER_ENV="${S_COMPILER:-/home/shuwen/tmp/s_compiler_improved}"

echo "repo root: $ROOT"
echo "using resolver: $RESOLVER"
echo "using initial S compiler: $S_COMPILER_ENV"

if [ ! -x "$RESOLVER" ]; then
  echo "resolver missing: $RESOLVER" >&2
  exit 1
fi
if [ ! -x "$S_COMPILER_ENV" ]; then
  echo "S compiler missing: $S_COMPILER_ENV" >&2
  exit 1
fi

ENTRY="src/cmd/compile/main.s"

echo "resolving dependencies for $ENTRY"
$RESOLVER "$ROOT" "$ENTRY" > "$TMPDIR/s_deps.txt"
cat "$TMPDIR/s_deps.txt"

echo "building entry with initial S compiler"
(
  cd "$ROOT/src"
  S_DISABLE_SELFHOSTED=1 python3 -m compiler build "$ROOT/$ENTRY" -o "$TMPDIR/s_compiler_stage1"
)
if [ -x "$TMPDIR/s_compiler_stage1" ]; then
  echo "stage1 compiler built: $TMPDIR/s_compiler_stage1"
  export S_COMPILER="$TMPDIR/s_compiler_stage1"
else
  echo "stage1 compiler not produced" >&2
  exit 1
fi

echo "attempting self-hosted full build with S_COMPILER=$S_COMPILER"
"$ROOT/misc/scripts/install_selfhost_compiler_launcher.sh" "$TMPDIR/s_final_compiler"
echo "done"
