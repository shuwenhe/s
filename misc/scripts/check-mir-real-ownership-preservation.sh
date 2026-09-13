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
        echo "mir real ownership preservation: missing $label" >&2
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
        echo "mir real ownership preservation: unexpected $label" >&2
        echo "  file: ${file#$root/}" >&2
        echo "  text: $needle" >&2
        exit 1
    fi
}

require_text "$mir_file" 'struct mir_borrow_stmt {' 'borrow statement payload'
require_text "$mir_file" 'string ref_name' 'borrow/reference identity'
require_text "$mir_file" 'mir_place place' 'borrowed place payload'
require_text "$mir_file" 'bool mutable' 'borrow mutability payload'
require_text "$mir_file" 'struct mir_ref_use_stmt {' 'reference use payload'
require_text "$mir_file" 'struct mir_ref_assign_stmt {' 'reference assignment payload'
require_text "$mir_file" 'borrow(mir_borrow_stmt)' 'borrow statement variant'
require_text "$mir_file" 'ref_use(mir_ref_use_stmt)' 'reference use statement variant'
require_text "$mir_file" 'ref_assign(mir_ref_assign_stmt)' 'reference assignment statement variant'
require_text "$mir_file" 'func mir_append_ownership_semantics_from_stmt' 'statement preservation helper'
require_text "$mir_file" 'func mir_append_ownership_semantics_from_expr' 'expression preservation helper'
require_text "$mir_file" 'expr.borrow(borrow_expr)' 'borrow expression preservation'
require_text "$mir_file" 'mir_statement::borrow(mir_borrow_stmt {' 'borrow statement emission'
require_text "$mir_file" 'mir_statement::ref_use(mir_ref_use_stmt {' 'reference use emission'
require_text "$mir_file" 'mir_statement::ref_assign(mir_ref_assign_stmt {' 'reference assignment emission'
require_text "$mir_file" 'mir_append_ownership_semantics_from_stmt(statements, block.statements[index])' 'compile.internal.mir lowering preservation'
require_text "$lower_file" 'use compile.internal.mir.mir_append_ownership_semantics_from_stmt' 'real lowering imports preservation helper'
require_text "$lower_file" 'make_entry_block(0, "entry", stmt_texts, block.statements' 'real lowering entry block preservation'
require_text "$lower_file" 'mir_append_ownership_semantics_from_stmt(statements, source_statements[i])' 'real lowering emits ownership semantic statement'

reject_text "$lower_file" 'analyze_ownership_liveness' 'solver call in real lowering'

echo "mir-real-ownership-preservation-check: ok"
