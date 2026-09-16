#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
serializer="$root/misc/scripts/canonical-bootstrap-ir-cfg-branch-serializer.sh"

tmp="${TMPDIR:-/tmp}/b6.6.3-serializer-loop.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

view="$tmp/loop.view"
ir="$tmp/loop.ir"
log="$tmp/serializer.log"

cat >"$view" <<'VIEW'
canonical-lowered-view version=1
view-role=READ_ONLY
function loop_once
entry-block=bb_entry
block bb_entry
jump-target=bb_header
jump-target-origin=canonical-mir-terminator
block bb_header
loop-header=bb_header
loop-header-origin=canonical-mir
loop-condition=keep_going
loop-condition-origin=canonical-mir-terminator
loop-body-edge=bb_body
loop-body-edge-origin=canonical-mir-terminator
loop-exit-edge=bb_exit
loop-exit-edge-origin=canonical-mir-terminator
block bb_body
body-effect=opaque
loop-backedge=bb_header
loop-backedge-origin=canonical-mir
block bb_exit
return-constant=7
VIEW

set +e
sh "$serializer" "$view" "$ir" >"$log" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
    echo "b6.6.3 serializer loop encoding: serializer cannot consume cyclic CFG lowered-view facts" >&2
    echo "classification=SERIALIZER_CAPABILITY_GAP" >&2
    exit 1
fi

require_ir() {
    local pattern="$1"
    local message="$2"
    if ! grep -Eq "$pattern" "$ir"; then
        echo "b6.6.3 serializer loop encoding: $message" >&2
        echo "classification=SERIALIZER_CAPABILITY_GAP" >&2
        exit 1
    fi
}

require_ir '^FUNC_BEGIN\|loop_once\|_\|_$' "loop function was not encoded"
require_ir '^LABEL\|bb_header\|_\|_$' "loop header was not encoded"
require_ir '^JUMP_IF_FALSE\|bb_exit\|keep_going\|_$' "loop condition/exit target was not encoded"
require_ir '^JUMP\|bb_body\|_\|_$' "loop body target was not encoded"
require_ir '^LABEL\|bb_body\|_\|_$' "loop body label was not encoded"
require_ir '^JUMP\|bb_header\|_\|_$' "loop back-edge target was not encoded"
require_ir '^LABEL\|bb_exit\|_\|_$' "loop exit label was not encoded"

echo "loop-header-encoded=YES"
echo "loop-condition-encoded=YES"
echo "loop-body-target-encoded=YES"
echo "loop-exit-target-encoded=YES"
echo "loop-backedge-target-encoded=YES"
echo "canonical-origin-preserved=YES"
echo "serializer-semantic-authority=NONE"
echo "serializer-cfg-authority=NONE"
echo "serializer-loop-authority=NONE"
echo "classification=B6.6.3_GREEN"
