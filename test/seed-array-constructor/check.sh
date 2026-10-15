#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-array-constructor.XXXXXX)
printf 'array constructor artifacts=%s\n' "$work"
cd "$root"
sources=(
    src/cmd/compile/seed/s_seed.c
    src/cmd/compile/seed/bootstrap/bootstrap.c
    src/cmd/compile/seed/lexical/lexer.c
    src/cmd/compile/seed/lexical/selfhost_bridge.c
    src/cmd/compile/seed/error/error.c
    src/cmd/compile/seed/syntax/parser.c
    src/cmd/compile/seed/semantic/analyzer.c
    src/cmd/compile/seed/intermediate/ir.c
    src/cmd/compile/seed/code/generator.c
    src/cmd/compile/seed/code/backend_registry.c
    src/cmd/compile/seed/code/native_backend.c
    src/cmd/compile/seed/code/standalone_amd64_backend.c
    src/cmd/compile/seed/runtime/network_windows.c
    src/cmd/compile/seed/runtime/runtime.c
)
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -DSEED_COMPILE_ONLY \
    test/seed-array-constructor/contract_test.c "${sources[@]}" -o "$work/contract-test"
timeout 30s "$work/contract-test"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror "${sources[@]}" -o "$work/s_seed"
"$work/s_seed" --compile-unit "$work/empty.ir" test/seed-array-constructor/empty_native.s
S_SOURCE_ROOT="$root" "$work/s_seed" --emit-bin "$work/empty.ir" "$work/hosted"
timeout 10s "$work/hosted"
S_SOURCE_ROOT="$root" "$work/s_seed" --emit-standalone-amd64 "$work/empty.ir" "$work/standalone"
timeout 10s "$work/standalone"
printf 'Hosted and Standalone empty array return: PASS\n'
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -DSEED_COMPILE_ONLY \
    src/cmd/compile/seed/testing/tests.c "${sources[@]}" -o "$work/seed-tests"
timeout 60s "$work/seed-tests"
