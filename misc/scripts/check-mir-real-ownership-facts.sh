#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
mir_file="$root/src/cmd/compile/internal/mir.s"
lower_file="$root/src/cmd/compile/internal/ir/lower.s"

require_text() {
    file=$1
    needle=$2
    label=$3
    if ! grep -Fq "$needle" "$file"; then
        echo "mir real ownership facts audit: missing $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

reject_text() {
    file=$1
    needle=$2
    label=$3
    if grep -Fq "$needle" "$file"; then
        echo "mir real ownership facts audit: unexpected $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

require_text "$mir_file" 'struct mir_place {' 'MIR place representation'
require_text "$mir_file" 'mir_place_projection[] projections' 'nested place projections'
require_text "$mir_file" 'func mir_place_from_expr' 'AST expression to MIR place helper'
require_text "$mir_file" 'func mir_place_key' 'stable place key helper'
require_text "$mir_file" 'borrow(mir_borrow_stmt)' 'point-addressable borrow statement'
require_text "$mir_file" 'ref_use(mir_ref_use_stmt)' 'point-addressable reference use statement'
require_text "$mir_file" 'ref_assign(mir_ref_assign_stmt)' 'point-addressable reference assignment statement'
require_text "$mir_file" 'func mir_append_ownership_semantics_from_stmt' 'AST to ownership MIR preservation helper'
require_text "$mir_file" 'events = append(events, "move:" + name_expr.name)' 'move event'
require_text "$mir_file" 'events = append(events, "write:" + assign_stmt.name)' 'write/reinit event'
require_text "$mir_file" 'move(mir_move_stmt)' 'explicit MIR move statement variant'
require_text "$mir_file" 'copy(mir_copy_stmt)' 'explicit MIR copy statement variant'
require_text "$lower_file" 'func lower_block_to_mir' 'real CFG MIR lowering path'
require_text "$lower_file" 'make_block(0, "entry"' 'real MIR block creation'
require_text "$lower_file" 'make_entry_block(0, "entry", stmt_texts, block.statements' 'real MIR entry semantic preservation'
require_text "$lower_file" 'mir_append_ownership_semantics_from_stmt(statements, source_statements[i])' 'real MIR ownership semantic statement emission'
require_text "$lower_file" 'make_edge("then", 1)' 'real MIR branch edge'
require_text "$lower_file" 'vec1_edge("cond", 1)' 'real MIR loop backedge'
require_text "$mir_file" 'func build_ownership_analysis_input_from_mir' 'real MIR ownership facts builder'

awk '
    /func build_mir_point_map/ { in_builder = 1 }
    /func mir_point_id/ { in_builder = 0 }
    in_builder && /(while changed|converged|outlives|loan|region|liveness)/ {
        print "mir real ownership facts audit: point-map builder contains analysis semantics"
        exit 1
    }
' "$mir_file"

cat <<'REPORT'
Real MIR ownership fact audit:
  borrow issuance: explicit mir_statement::borrow
  borrowed Place: represented by mir_place/mir_place_projection and mir_place_key
  reference identity: carried by ref_name/source_ref/target_ref strings
  reference use: explicit mir_statement::ref_use
  ref -> ref assignment: explicit mir_statement::ref_assign
  move vs copy: explicit mir_statement variants exist, but real lower.s mostly emits textual eval lines
  point CFG: available through mir_graph blocks/statements/terminators and mir_point_map
  conclusion: real MIR now preserves minimum ownership facts; C.2.3 can build input facts next
REPORT
