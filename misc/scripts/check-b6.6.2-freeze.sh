#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

bash "$root/misc/scripts/check-b6.6.2-lowered-view-loop-projection.sh" >/dev/null

cat <<'REPORT'
B6.6.2 Lowered-view Loop Projection
status=PASS/FROZEN

lowered-view-loop-header-visible=PROVEN
lowered-view-loop-condition-visible=PROVEN
lowered-view-loop-body-edge-visible=PROVEN
lowered-view-loop-exit-edge-visible=PROVEN
lowered-view-loop-backedge-visible=PROVEN

lowered-view-loop-reconstruction-authority=NONE
REPORT
