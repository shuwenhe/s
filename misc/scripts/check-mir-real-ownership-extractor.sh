#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
mir_file="$root/src/cmd/compile/internal/mir.s"
test_file="$root/src/cmd/compile/internal/tests/test_mir.s"

require_text() {
    file=$1
    needle=$2
    label=$3
    if ! grep -Fq "$needle" "$file"; then
        echo "mir real ownership extractor: missing $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

require_text "$mir_file" 'struct mir_ownership_analysis_input {' 'real MIR facts output'
require_text "$mir_file" 'func build_ownership_analysis_input_from_mir' 'real MIR facts extractor'
require_text "$mir_file" 'func mir_ownership_ref_id' 'MIR ref name to analysis ref id mapping'
require_text "$mir_file" 'mir_statement::borrow(borrow_stmt)' 'borrow fact extraction'
require_text "$mir_file" 'mir_statement::ref_use(use_stmt)' 'reference use fact extraction'
require_text "$mir_file" 'mir_statement::ref_assign(assign_stmt)' 'reference assignment fact extraction'
require_text "$mir_file" 'point := mir_point_id(points, graph.blocks[block_index].id, stmt_index)' 'semantic point to dense point mapping'
require_text "$mir_file" 'input.loan_points = append(input.loan_points, mir_add_point_value(0, point))' 'loan issue point fact'
require_text "$mir_file" 'input.region_points[ref_id] = mir_add_point_value(input.region_points[ref_id], point)' 'region use point fact'
require_text "$mir_file" 'input.outlives_from = append(input.outlives_from, source_ref)' 'outlives source direction'
require_text "$mir_file" 'input.outlives_to = append(input.outlives_to, target_ref)' 'outlives target direction'
require_text "$mir_file" 'func dump_ownership_analysis_input_from_mir' 'facts debug view'

awk '
    /func build_ownership_analysis_input_from_mir/ { in_extractor = 1 }
    /func mir_empty_ownership_analysis_input/ { in_extractor = 0 }
    in_extractor && /(while changed|converged|analyze_ownership_liveness|borrow conflict|move legality|compiler_fail)/ {
        print "mir real ownership extractor: extractor leaked solver or authority semantics"
        exit 1
    }
' "$mir_file"

require_text "$test_file" 'mir_statement::borrow(mir_borrow_stmt {' 'synthetic borrow MIR test'
require_text "$test_file" 'mir_statement::ref_assign(mir_ref_assign_stmt {' 'synthetic ref assign MIR test'
require_text "$test_file" 'mir_statement::ref_use(mir_ref_use_stmt {' 'synthetic ref use MIR test'
require_text "$test_file" 'PointCount = 4' 'point count expected fact'
require_text "$test_file" 'Ref(_2) = R0' 'first ref mapping'
require_text "$test_file" 'Ref(_3) = R1' 'second ref mapping'
require_text "$test_file" 'Loan0 issued = {P0} place=_1' 'loan issue expected fact'
require_text "$test_file" 'RefLoan(R0) = L0' 'borrow ref loan expected fact'
require_text "$test_file" 'RefLoan(R1) = L0' 'assigned ref loan expected fact'
require_text "$test_file" 'Outlives(R0,R1)' 'outlives direction expected fact'
require_text "$test_file" 'RegionPoint(R1) = {P2}' 'reference use expected fact'

echo "mir-real-ownership-extractor-check: ok"
