#!/usr/bin/env bash
set -euo pipefail

root=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
work=$(mktemp -d "${TMPDIR:-/tmp}/s-m2-pointer-binding.XXXXXX")
trap 'rm -rf "$work"' EXIT

"$root/bin/s_seed" --compile-unit "$work/demo.ir" \
  "$root/src/cmd/compile/bootstrap/bootstrap_demo.s" >"$work/seed.log" 2>&1 || true

if grep -q 'error\[4\] at 16:9: expected expression, got :=' "$work/seed.log"; then
  echo 'M2 pointer binding regression: still rejects the invalid bc* binding form' >&2
  cat "$work/seed.log" >&2
  exit 1
fi

echo 'M2 pointer binding regression: line 16 bc* parser error is cleared'
