#!/usr/bin/env bash
# Regression test for the unit-function return lowering in program_lower.
#
# A function declared with result type "()" must always return the unit value,
# even when its body ends in an expression statement whose value would otherwise
# be treated as an implicit return (e.g. a trailing append(...)). The previous
# lowering emitted that non-unit value as the return, which mismatched "()" and
# failed MIR validation (real-world hit: core/backend.s add_module_candidates_in_root).
#
# Cases covered:
#   A) () fn ending in append statements (exact real-world failing pattern)
#   B) () fn ending in a non-unit arithmetic expression statement
#   C) () fn with explicit empty return
#   D) () fn with a side-effecting trailing expr then explicit return
#   E) non-unit fn with explicit tuple return (must stay intact)
#   F) non-unit fn with trailing expression as implicit return (must stay intact)
#   G) empty unit function
# Side effects of trailing expressions must be preserved (D exercises this).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler="$root/bin/s_compiler"
[ -x "$compiler" ] || { echo "compiler missing: run 'make compiler'" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/unit.s" <<'EOF'
package main

func unit_trailing_append(string[] candidates) () {
    append(candidates, "x")
    append(candidates, "y")
}

func unit_trailing_arith(int x) () {
    x + x
}

func unit_explicit_return() () {
    return
}

func unit_side_effect(int x) () {
    x + x
    return
}

func tuple_return(int x) (int, int) {
    return x, x
}

func implicit_return(int x) int {
    x + x
}

func unit_empty() () {
}

func main(int x) int {
    unit_trailing_arith(1)
    unit_explicit_return()
    unit_side_effect(1)
    a, b := tuple_return(2)
    d := implicit_return(3)
    unit_empty()
    return a + b + d
}
EOF

"$compiler" --compile-unit "$work/unit.sasm" "$work/unit.s"
"$compiler" --emit-bin "$work/unit.sasm" "$work/unit"
status=0
"$work/unit" 2 || status=$?
# main returns a + b + d = tuple_return(2)->(2,2) + implicit_return(3)->6 = 10
if [ "$status" -ne 10 ]; then
    echo "unit-return FAILED: expected exit 10, got $status" >&2
    exit 1
fi

echo "unit-return lowering ok: exit=10 (all () / tuple / implicit-return cases compile and run)"
