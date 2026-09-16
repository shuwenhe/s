#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

bash "$root/misc/scripts/check-b6.6.1-freeze.sh"
bash "$root/misc/scripts/check-b6.6.2-freeze.sh"
bash "$root/misc/scripts/check-b6.6.3-freeze.sh"
bash "$root/misc/scripts/check-b6.6.4-loop-aot-runtime.sh"

echo "B6.6 Cyclic CFG / Loop=PASS/FROZEN"
echo "canonical-loop-authority=PROVEN"
echo "lowered-view-loop-projection=PROVEN"
echo "serializer-loop-representation=PROVEN"
echo "aot-loop-consumption=PROVEN"
echo "loop-header-entered=PROVEN"
echo "loop-body-entered=PROVEN"
echo "loop-backedge-taken=PROVEN"
echo "loop-header-reentered=PROVEN"
echo "loop-exit-edge-taken=PROVEN"
echo "native-result=7"
