#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

bash "$root/misc/scripts/check-b6.6.3-serializer-loop-encoding.sh"

echo "B6.6.3 Serializer encoding=PASS/FROZEN"
echo "serializer-loop-header-encoded=PROVEN"
echo "serializer-loop-condition-encoded=PROVEN"
echo "serializer-loop-body-target-encoded=PROVEN"
echo "serializer-loop-exit-target-encoded=PROVEN"
echo "serializer-loop-backedge-target-encoded=PROVEN"
echo "serializer-semantic-authority=NONE"
echo "serializer-cfg-authority=NONE"
