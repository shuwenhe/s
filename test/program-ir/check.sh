#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-program-ir-test.XXXXXX)
printf 'program-ir artifacts=%s\n' "$work"
# Hosted execution validates the S module implementation only, not native authority.
timeout 30s "$root/bin/s_seed" --compile-unit "$work/test.ir" \
    "$root/src/cmd/compile/internal/mir/program.s" "${1:-$root/test/program-ir/module_test.s}"
timeout 30s "$root/bin/s_seed" --emit-bin "$work/test.ir" "$work/test"
timeout 10s "$work/test"
