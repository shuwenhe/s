#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
serializer="$root/misc/scripts/canonical-bootstrap-ir-cfg-branch-serializer.sh"

tmp="${TMPDIR:-/tmp}/b6.5.3-serializer-branch.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

view="$tmp/branch.view"
ir="$tmp/branch.ir"
log="$tmp/serializer.log"

cat >"$view" <<'VIEW'
canonical-lowered-view version=1
view-role=READ_ONLY
function choose
entry-block=bb0
block bb0
branch-condition=flag
branch-condition-origin=canonical-mir-terminator
true-edge=bb9
true-edge-origin=canonical-mir-terminator
false-edge=bb8
false-edge-origin=canonical-mir-terminator
block bb9
return-constant=42
block bb8
return-constant=43
function main
entry-block=bb0
return-kind=int
call-target=choose
call-argument=1
VIEW

set +e
sh "$serializer" "$view" "$ir" >"$log" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "b6.5.3 serializer branch encoding: serializer cannot consume complete lowered-view branch facts" >&2
    echo "classification=SERIALIZER_CAPABILITY_GAP" >&2
    exit 1
fi

require_ir() {
    local pattern="$1"
    local message="$2"
    if ! grep -Eq "$pattern" "$ir"; then
        echo "b6.5.3 serializer branch encoding: $message" >&2
        echo "classification=SERIALIZER_CAPABILITY_GAP" >&2
        exit 1
    fi
}

require_ir '^PARAM\|flag\|_\|_$' "condition was not encoded from lowered-view"
require_ir '^JUMP_IF_FALSE\|bb8\|flag\|_$' "false target was not encoded from lowered-view"
require_ir '^LABEL\|bb9\|_\|_$' "true target was not encoded from lowered-view"
require_ir '^LABEL\|bb8\|_\|_$' "false label was not encoded from lowered-view"
require_ir '^RET\|42\|_\|_$' "true block payload was not preserved"
require_ir '^RET\|43\|_\|_$' "false block payload was not preserved"

echo "serializer-branch-condition-encoded=YES"
echo "serializer-true-target-encoded=YES"
echo "serializer-false-target-encoded=YES"
echo "branch-condition-origin=canonical-lowered-view"
echo "true-edge-origin=canonical-lowered-view"
echo "false-edge-origin=canonical-lowered-view"
echo "serializer-branch-authority=NONE"
echo "classification=B6.5.3_GREEN"
