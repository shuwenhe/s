#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-function-ssa.XXXXXX)
printf 'function-ssa artifacts=%s\n' "$work"
sources=(
    "$root/src/cmd/compile/internal/mir/program.s"
    "$root/src/cmd/compile/internal/ssa/program.s"
    "$root/src/cmd/compile/internal/ssa/function_lower.s"
)
for name in unit_test mir_call_metadata_test lower_test; do
    timeout 30s "$root/bin/s_seed" --compile-unit "$work/$name.ir" \
        "${sources[@]}" "$root/test/function-ssa/$name.s"
    timeout 30s "$root/bin/s_seed" --emit-bin "$work/$name.ir" "$work/$name"
    timeout 10s "$work/$name"
done
