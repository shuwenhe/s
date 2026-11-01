#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
lower_file="$root/src/cmd/compile/internal/ir/lower.s"

require() {
    local pattern="$1"
    local message="$2"
    if ! grep -Eq "$pattern" "$lower_file"; then
        echo "b6.6.2 lowered-view loop projection: $message" >&2
        echo "classification=EXPORT_VIEW_GAP" >&2
        exit 1
    fi
}

require 'func lowered_view_from_mir\(mir_graph graph\) string' \
    "missing lowered-view projection from finalized canonical MIR"
require 'loop-header=.*lowered_view_block_name\(block\.id\)' \
    "loop header identity is not projected from canonical block id"
require 'loop-header-origin=canonical-mir' \
    "loop header origin is not canonical MIR"
require 'loop-condition=.*condition\.value' \
    "loop condition is not projected from mir_terminator.condition"
require 'loop-condition-origin=canonical-mir-terminator' \
    "loop condition origin is not canonical MIR terminator"
require 'loop-body-edge=.*lowered_view_block_name\(edge\.target\)' \
    "loop body edge target is not projected from canonical edge target"
require 'loop-body-edge-origin=canonical-mir-terminator' \
    "loop body edge origin is not canonical MIR terminator"
require 'loop-exit-edge=.*lowered_view_block_name\(edge\.target\)' \
    "loop exit edge target is not projected from canonical edge target"
require 'loop-exit-edge-origin=canonical-mir-terminator' \
    "loop exit edge origin is not canonical MIR terminator"
require 'loop-backedge=.*lowered_view_block_name\(edge\.target\)' \
    "loop back-edge target is not projected from canonical edge target"
require 'loop-backedge-origin=canonical-mir' \
    "loop back-edge origin is not canonical MIR"

if awk '
    /func lowered_view_from_mir\(mir_graph graph\) string/ { in_view=1 }
    in_view && /while_expr|expr\.while|dump_expr/ { bad=1 }
    in_view && /^}/ { in_view=0 }
    END { exit bad ? 0 : 1 }
' "$lower_file"; then
    echo "b6.6.2 lowered-view loop projection: lowered-view projection must not parse or reconstruct while" >&2
    echo "classification=EXPORT_VIEW_GAP" >&2
    exit 1
fi

echo "lowered-view-loop-header-visible=YES"
echo "lowered-view-loop-condition-visible=YES"
echo "lowered-view-loop-body-edge-visible=YES"
echo "lowered-view-loop-exit-edge-visible=YES"
echo "lowered-view-loop-backedge-visible=YES"
echo "classification=B6.6.2_GREEN"
