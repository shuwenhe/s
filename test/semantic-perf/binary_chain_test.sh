#!/usr/bin/env bash
# Regression test for the binary-expression fast path in ca_expr_in_scope.
# A long operator chain must still compile to correct native code (guards the
# bottom-up type recomposition against the previous full re-inference path).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler="$root/bin/s_compiler"
[ -x "$compiler" ] || { echo "compiler missing: run 'make compiler'" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 101 occurrences of x (one plus a hundred "+ x") => 101 * x.
{
    echo "package main"
    printf 'func main(int x) int {\n    return x'
    for _ in $(seq 1 100); do printf ' + x'; done
    printf '\n}\n'
} > "$work/chain.s"

"$compiler" --compile-unit "$work/chain.sasm" "$work/chain.s"
"$compiler" --emit-bin "$work/chain.sasm" "$work/chain"
status=0
"$work/chain" 2 || status=$?
if [ "$status" -ne 202 ]; then
    echo "binary chain FAILED: expected 101*2=202, got $status" >&2
    exit 1
fi

# Mixed operators: x*3 - x => 2*x. With x=5 that is 10.
{
    echo "package main"
    echo 'func main(int x) int { return x * 3 - x }'
} > "$work/mixed.s"
"$compiler" --compile-unit "$work/mixed.sasm" "$work/mixed.s"
"$compiler" --emit-bin "$work/mixed.sasm" "$work/mixed"
status=0
"$work/mixed" 5 || status=$?
if [ "$status" -ne 10 ]; then
    echo "mixed operator FAILED: expected 2*5=10, got $status" >&2
    exit 1
fi

echo "binary fast-path correctness ok: chain=202, mixed=10"
