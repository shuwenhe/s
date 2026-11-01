#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-ownership-analysis-consistency.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

src="$work/facts.s"
cat >"$src" <<'SRC'
package consistency
func main() int {
    borrow_shared_field p _1 0
    q := p
    use_ref q
    move_field _1 0
    return 0
}
SRC

"$root/bin/s" --emit-mir-region-solver "$src" "$work/region.out"
"$root/bin/s" --emit-mir-nll-borrow-check "$src" "$work/borrow.out"
"$root/bin/s" --emit-mir-nll-shadow "$src" "$work/shadow.out"
"$root/bin/s" --emit-mir-ownership-solver-check "$src" "$work/pure.out"

if ! grep -Fq 'Region('\''r_p) = {P0, P2}' "$work/region.out"; then
    echo "mir ownership analysis consistency: region solver lost R_p facts" >&2
    cat "$work/region.out" >&2
    exit 1
fi

if ! grep -Fq 'Loan(L0) = {P0, P2}' "$work/region.out"; then
    echo "mir ownership analysis consistency: region solver lost loan facts" >&2
    cat "$work/region.out" >&2
    exit 1
fi

for file in "$work/borrow.out" "$work/shadow.out"; do
    if ! grep -Fq 'Loan(L0) = {P0, P2}' "$file" && ! grep -Fq 'LoanLivePoints(L0) = {P0, P2}' "$file"; then
        echo "mir ownership analysis consistency: diagnostic client disagrees on loan facts" >&2
        cat "$file" >&2
        exit 1
    fi
    if ! grep -Fq 'converged=true' "$file"; then
        echo "mir ownership analysis consistency: diagnostic client did not report convergence" >&2
        cat "$file" >&2
        exit 1
    fi
done

for expected in \
    'Region(R0) = {P1, P3}' \
    'Region(R1) = {P3}' \
    'LoanLivePoints(L0) = {P0, P1, P3}' \
    'converged=true'
do
    if ! grep -Fq "$expected" "$work/pure.out"; then
        echo "mir ownership analysis consistency: pure solver disagrees on canonical facts" >&2
        cat "$work/pure.out" >&2
        exit 1
    fi
done

echo "MIR ownership analysis consistency check passed"
