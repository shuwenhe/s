#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-ownership-solver.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

src="$work/solver.s"
out="$work/solver.out"
cat >"$src" <<'SRC'
package solver
func main() int { return 0 }
SRC

"$root/bin/s" --emit-mir-ownership-solver-check "$src" "$out"

for expected in \
    'ownership-solver-check' \
    'Region(R0) = {P1, P3}' \
    'Region(R1) = {P3}' \
    'LoanLivePoints(L0) = {P0, P1, P3}' \
    'OwnershipAnalysis(iterations=' \
    'converged=true'
do
    if ! grep -Fq "$expected" "$out"; then
        echo "mir ownership solver: missing $expected" >&2
        cat "$out" >&2
        exit 1
    fi
done

echo "MIR ownership solver check passed"
