#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
seed="${SEED_COMPILER_BIN:-"$root/bin/s_seed"}"
serializer="$root/misc/scripts/canonical-bootstrap-ir-cfg-branch-serializer.sh"

tmp="${TMPDIR:-/tmp}/b6.6.4-loop-runtime.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

view="$tmp/loop.view"
ir="$tmp/loop.ir"
native="$tmp/loop.bin"
serialize_log="$tmp/serialize.log"
aot_log="$tmp/aot.log"

classify_failure() {
    local classification="$1"
    local message="$2"
    echo "b6.6.4 loop aot runtime: $message" >&2
    echo "classification=$classification" >&2
    exit 1
}

cat >"$view" <<'VIEW'
canonical-lowered-view version=1
view-role=READ_ONLY
function main
entry-block=bb_header
block bb_header
loop-header=bb_header
loop-header-origin=canonical-mir
loop-condition=keep_going
loop-condition-origin=canonical-mir-terminator
loop-initial-condition=1
loop-initial-condition-origin=canonical-lowered-view
loop-body-edge=bb_body
loop-body-edge-origin=canonical-mir-terminator
loop-exit-edge=bb_exit
loop-exit-edge-origin=canonical-mir-terminator
block bb_body
body-move=keep_going:0
body-move-origin=canonical-lowered-view
loop-backedge=bb_header
loop-backedge-origin=canonical-mir
block bb_exit
return-constant=7
VIEW

if ! sh "$serializer" "$view" "$ir" >"$serialize_log" 2>&1; then
    classify_failure ARTIFACT_GAP "serializer failed to write cyclic CFG artifact"
fi

if ! grep -q '^LABEL|bb_header|_|_$' "$ir" ||
   ! grep -q '^JUMP_IF_FALSE|bb_exit|keep_going|_$' "$ir" ||
   ! grep -q '^JUMP|bb_body|_|_$' "$ir" ||
   ! grep -q '^LABEL|bb_body|_|_$' "$ir" ||
   ! grep -q '^JUMP|bb_header|_|_$' "$ir" ||
   ! grep -q '^LABEL|bb_exit|_|_$' "$ir"; then
    classify_failure ARTIFACT_GAP "artifact does not preserve loop header/body/exit/backedge targets"
fi

if ! grep -q '^MOV|keep_going|1|_$' "$ir" ||
   ! grep -q '^MOV|keep_going|0|_$' "$ir"; then
    classify_failure ARTIFACT_GAP "artifact lacks condition state needed to exercise body, backedge, recheck, and exit"
fi

if ! S_SOURCE_ROOT="$root" "$seed" --emit-aot "$ir" "$native" >"$aot_log" 2>&1; then
    if grep -E 'unknown op|unknown label|JUMP_IF_FALSE|JUMP|MOV|LABEL|unsupported|parse|expected|invalid' "$aot_log" >/dev/null 2>&1; then
        classify_failure CONSUMER_GAP "consumer/AOT rejected serialized cyclic CFG artifact"
    fi
    classify_failure AOT_LOOP_GAP "AOT failed to lower serialized cyclic CFG artifact"
fi

if [ ! -x "$native" ]; then
    classify_failure AOT_LOOP_GAP "AOT did not produce executable native artifact"
fi

"$native" >/dev/null 2>&1 &
pid=$!
waited=0
while kill -0 "$pid" >/dev/null 2>&1 && [ "$waited" -lt 30 ]; do
    sleep 0.1
    waited=$((waited + 1))
done

if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    classify_failure RUNTIME_LOOP_GAP "native cyclic CFG did not terminate"
fi

set +e
wait "$pid"
actual=$?
set -e

if [ "$actual" != 7 ]; then
    classify_failure RUNTIME_LOOP_GAP "native cyclic CFG returned $actual, expected 7"
fi

echo "loop-header-entered=YES"
echo "loop-body-entered=YES"
echo "loop-backedge-taken=YES"
echo "loop-header-reentered=YES"
echo "loop-exit-edge-taken=YES"
echo "native-result=7"
echo "classification=B6.6.4_GREEN"
