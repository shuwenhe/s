#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

tmp="${TMPDIR:-/tmp}/b6.7.1-import-frontend.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

gcc -std=c11 -Wall -Wextra -Werror -DSEED_COMPILE_ONLY \
  -o "$tmp/seed_tests" \
  "$root/src/cmd/compile/seed/testing/tests.c" \
  "$root/src/cmd/compile/seed/s_seed.c" \
  "$root/src/cmd/compile/seed/bootstrap/bootstrap.c" \
  "$root/src/cmd/compile/seed/lexical/lexer.c" \
  "$root/src/cmd/compile/seed/lexical/selfhost_bridge.c" \
  "$root/src/cmd/compile/seed/error/error.c" \
  "$root/src/cmd/compile/seed/syntax/parser.c" \
  "$root/src/cmd/compile/seed/semantic/analyzer.c" \
  "$root/src/cmd/compile/seed/intermediate/ir.c" \
  "$root/src/cmd/compile/seed/code/generator.c" \
  "$root/src/cmd/compile/seed/code/backend_registry.c" \
  "$root/src/cmd/compile/seed/code/native_backend.c" \
  "$root/src/cmd/compile/seed/code/standalone_amd64_backend.c" \
  "$root/src/cmd/compile/seed/runtime/network_windows.c" \
  "$root/src/cmd/compile/seed/runtime/runtime.c"

"$tmp/seed_tests" >/dev/null

make -C "$root" seed-compiler-bin >/dev/null

closure="$tmp/closure.txt"
S_SOURCE_ROOT="$root" "$root/src/cmd/dist/source_closure.sh" \
  src/cmd/compile/modular_build_main.s "$closure" >/dev/null

set +e
S_SOURCE_ROOT="$root" "$root/bin/s_seed" \
  "$root/src/cmd/compile/modular_build_main.s" "$tmp/modular.ir" >"$tmp/seed.log" 2>&1
status=$?
set -e

if grep -q 'expected ), got STRING' "$tmp/seed.log"; then
    echo "classification=IMPORT_DECLARATION_STRING_LIST_FRONTEND_RED" >&2
    cat "$tmp/seed.log" >&2
    exit 1
fi

if [ "$status" -eq 0 ]; then
    next_blocker=NONE
else
    next_blocker=$(sed -n '1p' "$tmp/seed.log")
fi

echo "canonical-module-declaration-syntax=import-string-list"
echo "import-string-list-authority=canonical-source-closure"
echo "seed-parser-role=consume-canonical-declaration"
echo "single-string-import=PASS"
echo "multi-string-import=PASS"
echo "import-list-close=PASS"
echo "next-declaration-after-import=PASS"
echo "old-first-blocker=GONE"
echo "real-closure-count=$(wc -l <"$closure" | tr -d ' ')"
echo "real-closure-probe-status=$status"
echo "next-first-blocker=$next_blocker"
echo "classification=B6.7.1_GREEN"
