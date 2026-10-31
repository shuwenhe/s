#!/usr/bin/env bash
# Build and run the ssa check_func functional self-test.
# Exit 0 means every positive/negative case passed.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
seed="$root/bin/s_seed"
[ -x "$seed" ] || { echo "seed compiler missing: run 'make seed-compiler-bin'" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"$seed" --compile-native-unit "$work/ssa_selftest.ir" \
    "$root/src/cmd/compile/internal/ssa/value.s" \
    "$root/src/cmd/compile/internal/ssa/block.s" \
    "$root/src/cmd/compile/internal/ssa/func.s" \
    "$root/src/cmd/compile/internal/ssa/op.s" \
    "$root/src/cmd/compile/internal/ssa/check.s" \
    "$root/test/ssa-check/check_selftest.s"
"$seed" --emit-standalone-amd64 "$work/ssa_selftest.ir" "$work/ssa_selftest"
status=0
"$work/ssa_selftest" || status=$?
if [ "$status" -ne 0 ]; then
    echo "ssa check_func self-test FAILED: case code $status" >&2
    exit 1
fi
echo "ssa check_func self-test passed: all positive/negative cases ok"
