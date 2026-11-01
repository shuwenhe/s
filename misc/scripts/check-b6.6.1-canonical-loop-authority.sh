#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
lower_file="$root/src/cmd/compile/internal/ir/lower.s"

require() {
    local pattern="$1"
    local message="$2"
    if ! grep -Eq "$pattern" "$lower_file"; then
        echo "b6.6.1 canonical loop authority: $message" >&2
        echo "classification=CANONICAL_LOOP_LOWERING_GAP" >&2
        exit 1
    fi
}

require 'expr\.while\(while_expr\)' \
    "canonical while lowering case is absent"
require 'make_entry_block\(0, "entry", stmt_texts, block\.statements, "jump", vec1_edge\("cond", 1\)\)' \
    "loop entry does not target canonical header"
require 'while_condition := option\.some\(mir_operand[[:space:]]*\{' \
    "loop header terminator does not bind canonical condition"
require 'make_block_with_condition\(1, "while\.cond", cond_lines, "branch", while_condition, cond_edges\)' \
    "loop header branch terminator does not store condition"
require 'cond_edges = append\(cond_edges, make_edge\("true", 2\)\)' \
    "loop body edge is not canonical"
require 'cond_edges = append\(cond_edges, make_edge\("false", 3\)\)' \
    "loop exit edge is not canonical"
require 'make_block\(2, "while\.body", body_lines, "jump", vec1_edge\("cond", 1\)\)' \
    "loop back-edge to header is not canonical"
require 'make_block\(3, "while\.exit"' \
    "loop exit block identity is not canonical"

echo "canonical-loop-header-visible=YES"
echo "canonical-loop-condition-visible=YES"
echo "canonical-loop-body-edge-visible=YES"
echo "canonical-loop-exit-edge-visible=YES"
echo "canonical-loop-backedge-visible=YES"
echo "classification=B6.6.1_GREEN"
