#!/usr/bin/env bash
set -euo pipefail

root=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
work=$(mktemp -d "${TMPDIR:-/tmp}/s-m2-pointer-binding.XXXXXX")
trap 'rm -rf "$work"' EXIT

"$root/bin/s_seed" --compile-unit "$work/demo.ir" \
  "$root/src/cmd/compile/bootstrap/bootstrap_demo.s" >"$work/seed.log" 2>&1 || true

if grep -Eq 'error\[4\] at (16|49):[0-9]+: expected expression, got :=' "$work/seed.log"; then
  echo 'M2 pointer binding regression: still rejects a historical star-suffixed binding' >&2
  cat "$work/seed.log" >&2
  exit 1
fi

grep -Fq 'bc_ptr := alloc(bootstrap_compiler)' "$root/src/cmd/compile/bootstrap/bootstrap_demo.s"
grep -Fq 'compiler_ptr := bootstrap_compiler_new()' "$root/src/cmd/compile/bootstrap/bootstrap_demo.s"
if grep -Eq '\b(bc|compiler)\*([[:space:]]*):=' "$root/src/cmd/compile/bootstrap/bootstrap_demo.s"; then
  echo 'M2 pointer binding regression: invalid star-suffixed binding remains' >&2
  exit 1
fi

echo 'M2 pointer binding regression: bc* and compiler* errors are cleared'
