#!/usr/bin/env bash
set -euo pipefail

root=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
work=$(mktemp -d "${TMPDIR:-/tmp}/s-m2-slice.XXXXXX")
trap 'rm -rf "$work"' EXIT

cat >"$work/slices.s" <<'SOURCE'
package probe

func main() int {
    xs := int[]()
    a := xs[1]
    b := xs[1:]
    c := xs[:3]
    d := xs[1:3]
    e := xs[:]
    return 0
}
SOURCE

"$root/bin/s_seed" --dump-ast "$work/slices.s" "$work/slices.ast" >"$work/seed.log" 2>&1
test "$(grep -c 'INDEX_EXPR' "$work/slices.ast")" -eq 2
test "$(grep -c 'SLICE_EXPR' "$work/slices.ast")" -eq 4
echo 'M2 slice expression regression: index and four slice forms preserved in AST'
