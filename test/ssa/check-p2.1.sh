#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-p2-ssa.XXXXXX)
printf 'p2.1 artifacts=%s\n' "$work"
timeout 30s "$root/bin/s_seed" --compile-unit "$work/test.ir" \
    "$root/src/cmd/compile/internal/ssa/program.s" "$root/test/ssa/p2_representation_test.s"
timeout 30s "$root/bin/s_seed" --emit-bin "$work/test.ir" "$work/test"
timeout 10s "$work/test"
