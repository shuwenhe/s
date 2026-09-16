#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

bash "$root/misc/scripts/check-b6.6.1-canonical-loop-authority.sh" >/dev/null

cat <<'REPORT'
B6.6.1 Canonical Loop / Back-edge Authority
status=PASS/FROZEN

canonical-loop-header-authority=PROVEN
canonical-loop-condition-authority=PROVEN
canonical-loop-body-edge-authority=PROVEN
canonical-loop-exit-edge-authority=PROVEN
canonical-loop-backedge-authority=PROVEN

downstream-loop-reconstruction-authority=NONE
REPORT
