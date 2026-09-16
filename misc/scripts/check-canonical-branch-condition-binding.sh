#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

mir_file="$root/src/cmd/compile/internal/mir.s"
lower_file="$root/src/cmd/compile/internal/ir/lower.s"

require() {
    local file="$1"
    local pattern="$2"
    local message="$3"
    if ! grep -Eq "$pattern" "$file"; then
        echo "canonical branch condition binding: $message" >&2
        echo "classification=CANONICAL_LOWERING_GAP" >&2
        exit 1
    fi
}

require "$mir_file" 'option\[mir_operand\][[:space:]]+condition' \
    "mir_terminator does not carry a canonical condition binding"
require "$lower_file" 'branch_condition := option\.some\(mir_operand[[:space:]]*\{' \
    "if lowering does not bind the branch condition into the terminator"
require "$lower_file" 'make_entry_block_with_condition\(0, "entry", stmt_texts, block\.statements, "branch", branch_condition, entry_edges\)' \
    "if lowering does not pass the branch condition into the finalized terminator"
require "$lower_file" 'make_block_with_condition\(id, label, lines, term_kind, option\.none, edges\)' \
    "non-branch terminators do not explicitly mark condition absence"
require "$lower_file" 'make_entry_block_with_condition\(id, label, lines, source_statements, term_kind, option\.none, edges\)' \
    "entry non-branch terminators do not explicitly mark condition absence"
require "$lower_file" 'substitute_const_text\(s\.dump_expr\(if_expr\.condition\.value\)' \
    "if lowering does not derive condition text from the canonical if expression"

echo "canonical-branch-condition-visible=YES"
echo "classification=B6.5.1_GREEN"
