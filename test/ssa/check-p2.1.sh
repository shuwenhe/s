#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-p2-ssa.XXXXXX)
printf 'p2.1 artifacts=%s\n' "$work"
for test_name in p2_representation_test p2_verifier_test p2_cfg_test; do
    timeout 30s "$root/bin/s_seed" --compile-unit "$work/$test_name.ir" \
        "$root/src/cmd/compile/internal/ssa/program.s" "$root/test/ssa/$test_name.s"
    timeout 30s "$root/bin/s_seed" --emit-bin "$work/$test_name.ir" "$work/$test_name"
    timeout 10s "$work/$test_name"
done
