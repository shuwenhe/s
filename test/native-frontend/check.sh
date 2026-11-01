#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-frontend.XXXXXX)
printf 'Native frontend artifacts=%s\n' "$work"
sources=("$root/src/cmd/compile/internal/compiler/frontend_core.s"
         "$root/src/cmd/compile/internal/compiler/frontend.s"
         "$root/src/cmd/compile/internal/mir/program.s")
if [[ -f "$root/src/cmd/compile/internal/compiler/native_frontend.s" ]]; then
    sources+=("$root/src/cmd/compile/internal/compiler/native_frontend.s")
fi
sources+=("$root/test/native-frontend/frontend_test.s")
timeout 30s "$root/bin/s_seed" --compile-unit "$work/frontend.ir" "${sources[@]}"
S_SOURCE_ROOT="$root" timeout 60s "$root/bin/s_seed" --emit-bin "$work/frontend.ir" "$work/frontend"
timeout 30s "$work/frontend" "$root/test/native-frontend/program.s"
