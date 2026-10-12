#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

lower_file="$root/src/cmd/compile/internal/ir/lower.s"
require() {
    local file="$1"
    local pattern="$2"
    local message="$3"
    if ! grep -Eq "$pattern" "$file"; then
        echo "b6.5.2 lowered-view branch projection: $message" >&2
        echo "classification=EXPORT_VIEW_GAP" >&2
        exit 1
    fi
}

require "$lower_file" 'func lowered_view_from_mir\(mir_graph graph\) string' \
    "missing lowered-view projection from finalized canonical MIR"
require "$lower_file" 'terminator\.condition' \
    "lowered-view projection does not read mir_terminator.condition"
require "$lower_file" 'edge\.label == "then"' \
    "lowered-view projection does not read canonical then target"
require "$lower_file" 'true-edge=.*edge\.target' \
    "lowered-view projection does not export canonical then target"
require "$lower_file" 'edge\.label == "else"' \
    "lowered-view projection does not read canonical else target"
require "$lower_file" 'false-edge=.*edge\.target' \
    "lowered-view projection does not export canonical else target"
require "$lower_file" 'branch-condition-origin=canonical-mir-terminator' \
    "lowered-view output does not declare canonical branch condition origin"
require "$lower_file" 'true-edge-origin=canonical-mir-terminator' \
    "lowered-view output does not declare canonical true edge origin"
require "$lower_file" 'false-edge-origin=canonical-mir-terminator' \
    "lowered-view output does not declare canonical false edge origin"

echo "lowered-view-branch-condition-visible=YES"
echo "lowered-view-true-target-visible=YES"
echo "lowered-view-false-target-visible=YES"
echo "classification=B6.5.2_GREEN"
