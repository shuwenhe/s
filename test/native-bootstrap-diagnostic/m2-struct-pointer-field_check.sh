#!/usr/bin/env bash
set -euo pipefail

root=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
work=$(mktemp -d "${TMPDIR:-/tmp}/s-m2-struct-pointer.XXXXXX")
trap 'rm -rf "$work"' EXIT

cat >"$work/struct_pointer.s" <<'SOURCE'
package probe

struct pair {
    left* left,
    right right,
}

func main() int {
    pair { left* left, right right, }
    return 0
}
SOURCE

"$root/bin/s_seed" --dump-ast "$work/struct_pointer.s" "$work/struct_pointer.ast" >"$work/seed.log" 2>&1
grep -Fq 'STRUCT_EXPR' "$work/struct_pointer.ast"
grep -Fq 'fields=2' "$work/struct_pointer.ast"
echo 'M2 struct pointer field regression: pointer and ordinary fields preserved'
