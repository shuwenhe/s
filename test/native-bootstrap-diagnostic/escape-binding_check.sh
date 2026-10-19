#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
source_file="$root/src/cmd/compile/internal/escape/escape.s"
work=$(mktemp -d /tmp/s-escape-bindings.XXXXXX)
# Parse the real function signatures in isolation: unrelated for-in bodies
# must not mask whether the fixed parameter bindings reach the AST correctly.
awk '/^func batch_(init_func|walk_func|param_tag)\(/ { print; print "}" }' \
    "$source_file" > "$work/signatures.s"
"$root/bin/s_seed" --dump-ast "$work/signatures.s" "$work/signatures.ast"
if [[ $(rg -c 'param=function_decl type=ir.func$' "$work/signatures.ast") != 3 ]]; then
    echo 'FAIL: escape function parameters did not retain their name/type in AST' >&2
    exit 1
fi
# fn is a reserved declaration keyword, never an ordinary binding/reference.
# This file uses func for declarations; every standalone fn was a legacy name.
if rg -n '\bfn\b' "$source_file"; then
    echo 'FAIL: escape analysis still binds or references reserved fn' >&2
    exit 1
fi
echo 'Escape reserved binding audit: PASS (for-in support is a separate gate)'
