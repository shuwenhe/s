#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN_ROOT="$ROOT/bin"
TMPDIR="${TMPDIR:-/home/shuwen/tmp}"
HELLO_OUT="$TMPDIR/s_bootstrap_hello"
SUM_OUT="$TMPDIR/s_bootstrap_sum"
HELLO_EXPECTED="hello, world"
SUM_EXPECTED="5050"

if [ ! -x "$BIN_ROOT/s-native" ]; then
  echo "missing native runner: $BIN_ROOT/s-native" >&2
  exit 1
fi
if [ ! -x "$BIN_ROOT/s-selfhosted" ]; then
  echo "missing selfhosted launcher: $BIN_ROOT/s-selfhosted" >&2
  exit 1
fi

"$BIN_ROOT/s-native" check "$ROOT/src/cmd/compile/main.s"
"$BIN_ROOT/s-selfhosted" check "$ROOT/src/cmd/compile/main.s"

"$BIN_ROOT/s-native" build "$ROOT/misc/examples/s/hello.s" -o "$HELLO_OUT"
if [ "$("$HELLO_OUT")" != "$HELLO_EXPECTED" ]; then
  echo "unexpected hello output" >&2
  exit 1
fi

"$BIN_ROOT/s-native" build "$ROOT/misc/examples/s/sum.s" -o "$SUM_OUT"
if [ "$("$SUM_OUT")" != "$SUM_EXPECTED" ]; then
  echo "unexpected sum output" >&2
  exit 1
fi

echo "bootstrap verification passed"
