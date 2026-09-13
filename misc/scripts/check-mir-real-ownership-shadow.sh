#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
mir_file="$root/src/cmd/compile/internal/mir.s"
test_file="$root/src/cmd/compile/internal/tests/test_mir.s"
compiler_file="$root/src/cmd/compile/compiler.s"
driver_file="$root/misc/scripts/s-driver.sh"

require_text() {
    file=$1
    needle=$2
    label=$3
    if ! grep -Fq -- "$needle" "$file"; then
        echo "mir real ownership shadow: missing $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

reject_text() {
    file=$1
    needle=$2
    label=$3
    if grep -Fq -- "$needle" "$file"; then
        echo "mir real ownership shadow: unexpected $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

require_text "$mir_file" 'func dump_ownership_shadow_from_mir(mir_graph graph) string' 'real MIR shadow client'
require_text "$mir_file" 'facts := build_ownership_facts_from_mir(graph, points)' 'real MIR extractor feed'
require_text "$mir_file" 'analysis := analyze_ownership_liveness(facts.input)' 'shared solver feed'
require_text "$mir_file" 'LoanLivePoints(L" + to_string(i) + ") = " + mir_points_string(analysis.loan_live_points[i])' 'loan live points output'
require_text "$test_file" 'expected_shadow := "RealMIROwnershipShadow' 'shadow regression expectation'
require_text "$test_file" 'RealMIRFacts(point_count=4, refs=2, loans=1, outlives=1)' 'shadow facts summary expectation'
require_text "$test_file" 'LoanLivePoints(L0) = {P0,P2}' 'shared solver shadow expectation'
require_text "$test_file" 'dump_ownership_shadow_from_mir(fact_graph)' 'real MIR shadow regression call'

reject_text "$compiler_file" 'compiler_emit_mir_real_ownership_shadow' 'monolithic fixture emitter'
reject_text "$compiler_file" 'Point(P0) = BB0(entry):stmt0 Borrow(_2, _1)' 'hard-coded shadow fixture'
reject_text "$driver_file" '--emit-mir-real-ownership-shadow' 'driver fixture flag'

echo "mir-real-ownership-shadow-check: ok"
