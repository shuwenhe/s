#!/usr/bin/env bash
set -euo pipefail

root=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
work=$(mktemp -d "${TMPDIR:-/tmp}/s-m2-cast-boundary.XXXXXX")
trap 'rm -rf "$work"' EXIT

cat >"$work/cast_boundary.s" <<'SOURCE'
package probe

func main() int {
    code_offset := 120 as int64
    image_base := 0x400000 as int64
    return 0
}
SOURCE

if ! "$root/bin/s_seed" --dump-ast "$work/cast_boundary.s" "$work/cast_boundary.ast" >"$work/seed.log" 2>&1; then
    cat "$work/seed.log" >&2
    exit 1
fi

test "$(grep -c 'LET_STMT .*name=code_offset' "$work/cast_boundary.ast")" -eq 1
test "$(grep -c 'LET_STMT .*name=image_base' "$work/cast_boundary.ast")" -eq 1
echo 'M2 cast boundary regression: consecutive cast declarations preserved in AST'
