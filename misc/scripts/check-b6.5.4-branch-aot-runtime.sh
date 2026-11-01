#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
seed="${SEED_COMPILER_BIN:-"$root/bin/s_seed"}"
serializer="$root/misc/scripts/canonical-bootstrap-ir-cfg-branch-serializer.sh"

tmp="${TMPDIR:-/tmp}/b6.5.4-branch-runtime.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

write_view() {
    local arg="$1"
    local output="$2"
    cat >"$output" <<VIEW
canonical-lowered-view version=1
view-role=READ_ONLY
function choose
entry-block=bb0
block bb0
branch-condition=x
branch-condition-origin=canonical-mir-terminator
true-edge=bb_true
true-edge-origin=canonical-mir-terminator
false-edge=bb_false
false-edge-origin=canonical-mir-terminator
block bb_true
return-constant=42
block bb_false
return-constant=43
function main
entry-block=bb0
return-kind=int
call-target=choose
call-argument=$arg
VIEW
}

classify_failure() {
    local classification="$1"
    local message="$2"
    echo "b6.5.4 branch aot runtime: $message" >&2
    echo "classification=$classification" >&2
    exit 1
}

run_case() {
    local arg="$1"
    local expected="$2"
    local stem="$tmp/choose_$arg"
    local view="$stem.view"
    local ir="$stem.ir"
    local native="$stem.bin"
    local serialize_log="$stem.serialize.log"
    local aot_log="$stem.aot.log"
    local actual

    write_view "$arg" "$view"

    if ! sh "$serializer" "$view" "$ir" >"$serialize_log" 2>&1; then
        classify_failure ARTIFACT_GAP "serializer failed to write branch artifact for choose($arg)"
    fi

    if ! grep -q '^JUMP_IF_FALSE|bb_false|x|_$' "$ir"; then
        classify_failure ARTIFACT_GAP "artifact does not preserve branch condition and false target for choose($arg)"
    fi
    if ! grep -q '^LABEL|bb_true|_|_$' "$ir" || ! grep -q '^LABEL|bb_false|_|_$' "$ir"; then
        classify_failure ARTIFACT_GAP "artifact does not preserve true/false labels for choose($arg)"
    fi

    if ! S_SOURCE_ROOT="$root" "$seed" --emit-aot "$ir" "$native" >"$aot_log" 2>&1; then
        if grep -E 'unknown op|unknown label|JUMP_IF_FALSE|unsupported|parse|expected|invalid' "$aot_log" >/dev/null 2>&1; then
            classify_failure CONSUMER_GAP "consumer/AOT rejected serialized branch artifact for choose($arg)"
        fi
        classify_failure AOT_BRANCH_GAP "AOT failed to lower serialized branch artifact for choose($arg)"
    fi

    if [ ! -x "$native" ]; then
        classify_failure AOT_BRANCH_GAP "AOT did not produce executable native artifact for choose($arg)"
    fi

    set +e
    "$native" >/dev/null 2>&1
    actual=$?
    set -e

    if [ "$actual" != "$expected" ]; then
        classify_failure RUNTIME_BRANCH_GAP "choose($arg) returned $actual, expected $expected"
    fi
}

run_case 1 42
run_case 0 43

echo "artifact-branch-encoding=PROVEN"
echo "consumer-branch-artifact=PROVEN"
echo "aot-branch-lowering=PROVEN"
echo "true-path-runtime=PROVEN"
echo "false-path-runtime=PROVEN"
echo "choose(1)=42"
echo "choose(0)=43"
echo "classification=B6.5.4_GREEN"
