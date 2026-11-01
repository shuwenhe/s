#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
stage0=${1:-$root/src/cmd/compile/stage0/stage0.c}

if [ ! -f "$stage0" ]; then
    echo "stage0-freeze-check=FAIL"
    echo "reason=stage0-source-missing"
    exit 1
fi

subset=$root/src/cmd/compile/stage0/bootstrap_subset.c
if [ ! -f "$subset" ]; then
    echo "stage0-freeze-check=FAIL"
    echo "reason=bootstrap-subset-source-missing"
    exit 1
fi

if grep -Eq 'seed_compile|s_seed|runtime_execute|semantic_analyze|parser_parse|lexer_scan|ir_generate|emit_native_from_ir|ownership|nll|typecheck|monomorph|ssa_lower' "$stage0" "$subset"; then
    echo "stage0-freeze-check=FAIL"
    echo "reason=stage0-contains-production-authority-token"
    grep -En 'seed_compile|s_seed|runtime_execute|semantic_analyze|parser_parse|lexer_scan|ir_generate|emit_native_from_ir|ownership|nll|typecheck|monomorph|ssa_lower' "$stage0" "$subset" || true
    exit 1
fi

echo "stage0-freeze-check=PASS"
echo "stage0-freeze-policy=bootstrap-mechanics-only"
