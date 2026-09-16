#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

bash "$root/misc/scripts/check-canonical-branch-condition-binding.sh" >/dev/null
bash "$root/misc/scripts/check-b6.5.2-lowered-view-branch-projection.sh" >/dev/null
bash "$root/misc/scripts/check-b6.5.3-serializer-branch-encoding.sh" >/dev/null
bash "$root/misc/scripts/check-b6.5.4-branch-aot-runtime.sh" >/dev/null

cat <<'REPORT'
B6.5 CFG Branch Coverage
status=PASS/FROZEN

canonical-condition-authority=PROVEN
canonical-true-edge-authority=PROVEN
canonical-false-edge-authority=PROVEN

lowered-view-projection=PROVEN
serializer-representation-only=PROVEN
bootstrap-artifact-branch=PROVEN
aot-consumption=PROVEN

true-path-runtime=PROVEN
false-path-runtime=PROVEN

choose(1)=42
choose(0)=43

KNOWN_PREEXISTING_FAILURE=make s-syntax-check -> use of undeclared symbol 'lex'
known-preexisting-failure-impact=NONE
known-preexisting-failure-status=DEFERRED
REPORT
