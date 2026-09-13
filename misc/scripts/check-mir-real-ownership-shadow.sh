#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-real-shadow.XXXXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

input="$tmpdir/real_shadow.s"
out="$tmpdir/real_shadow.mir"

cat > "$input" <<'SRC'
func main() int {
    return 0
}
SRC

"$root/bin/s" --emit-mir-real-ownership-shadow "$input" "$out"

require_text() {
    needle=$1
    label=$2
    if ! grep -Fq "$needle" "$out"; then
        echo "mir real ownership shadow: missing $label" >&2
        echo "  text: $needle" >&2
        echo "---- output ----" >&2
        cat "$out" >&2
        exit 1
    fi
}

require_text 'RealMIROwnershipShadow' 'shadow header'
require_text 'RealMIRFacts(point_count=4, refs=2, loans=1, outlives=1)' 'real MIR facts summary'
require_text 'Point(P0) = BB0(entry):stmt0 Borrow(_2, _1)' 'borrow point'
require_text 'Point(P1) = BB0(entry):stmt1 RefAssign(_3, _2)' 'ref assign point'
require_text 'Point(P2) = BB0(entry):stmt2 RefUse(_3)' 'ref use point'
require_text 'Point(P3) = BB0(entry):term' 'terminator point'
require_text 'Region(R0) = {P0, P2}' 'shared solver propagated source region'
require_text 'Region(R1) = {P2}' 'shared solver retained use region'
require_text 'LoanLivePoints(L0) = {P0, P2}' 'shared solver loan live points'
require_text 'SharedSolverShadow(iterations=' 'shared solver shadow result'
require_text 'converged=true' 'solver convergence'

echo "mir-real-ownership-shadow-check: ok"
