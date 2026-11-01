#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-unit-ssa.XXXXXX)
trap 'rm -rf "$work"' EXIT
"$root/bin/s_seed" --compile-unit "$work/unit.ir" "$root/src/cmd/compile/internal/mir/program.s" "$root/src/cmd/compile/internal/mir/program_enum.s" "$root/src/cmd/compile/internal/ssa/program.s" "$root/src/cmd/compile/internal/ssa/function_lower.s" "$root/test/function-ssa/unit_test.s"
"$root/bin/s_seed" --emit-bin "$work/unit.ir" "$work/unit"
timeout 15 "$work/unit"
echo 'independent SSA unit type and constant validation: PASS'
