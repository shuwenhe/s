#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-region-solver.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

cat >"$work/chain.s" <<'SRC'
package regionsolver
func main() int {
    borrow_mut_field p _1 0
    q := p
    r := q
    use_ref r
    return 0
}
SRC

cat >"$work/diamond.s" <<'SRC'
package regionsolver
func main() int {
    borrow_shared_field p _1 0
    q := p
    r := p
    s := q
    use_ref s
    use_ref r
    return 0
}
SRC

cat >"$work/cycle.s" <<'SRC'
package regionsolver
func main() int {
    borrow_shared_field p _1 0
    q := p
    p := q
    use_ref p
    return 0
}
SRC

"$root/bin/s" --emit-mir-region-solver "$work/chain.s" "$work/chain.mir"
for expected in \
    "Region('r_r) = {P3}" \
    "Region('r_q) = {P3}" \
    "Region('r_p) = {P0, P3}" \
    'Loan(L0) = {P0, P3}' \
    'RegionSolver(iterations=' \
    'converged=true)'
do
    if ! grep -Fq "$expected" "$work/chain.mir"; then
        echo "mir region solver: chain did not propagate expected point: $expected" >&2
        cat "$work/chain.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-region-solver "$work/diamond.s" "$work/diamond.mir"
for expected in \
    "Region('r_s) = {P4}" \
    "Region('r_q) = {P4}" \
    "Region('r_r) = {P5}" \
    "Region('r_p) = {P0, P4, P5}" \
    'Loan(L0) = {P0, P4, P5}'
do
    if ! grep -Fq "$expected" "$work/diamond.mir"; then
        echo "mir region solver: diamond did not reach fixed-point closure: $expected" >&2
        cat "$work/diamond.mir" >&2
        exit 1
    fi
done

"$root/bin/s" --emit-mir-region-solver "$work/cycle.s" "$work/cycle.mir"
for expected in \
    "Region('r_p) = {P0, P3}" \
    "Region('r_q) = {P0, P3}" \
    'Loan(L0) = {P0, P3}' \
    'converged=true)'
do
    if ! grep -Fq "$expected" "$work/cycle.mir"; then
        echo "mir region solver: cycle should converge stably: $expected" >&2
        cat "$work/cycle.mir" >&2
        exit 1
    fi
done

echo "MIR region solver check passed"
