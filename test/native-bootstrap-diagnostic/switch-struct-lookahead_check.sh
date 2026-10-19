#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-switch-lookahead.XXXXXX")
trap 'rm -rf "$work"' EXIT

cat >"$work/switch.s" <<'SRC'
package probe
enum kind { a, b }
func test(kind x) int {
    switch x {
        case a: return 1
        case b: return 2
    }
    0
}
SRC

"$root/bin/s_seed" --dump-ast "$work/switch.s" "$work/switch.ast" >"$work/seed.log" 2>&1
rg -q 'FN_STMT.*name=test' "$work/switch.ast"
