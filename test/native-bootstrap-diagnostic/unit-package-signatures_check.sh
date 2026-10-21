#!/usr/bin/env bash
set -euo pipefail
root=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
seed=${S_SEED:-$root/bin/s_seed}
work=$(mktemp -d "${TMPDIR:-/tmp}/s-unit-package-signatures.XXXXXX")
fixtures="$root/test/native-bootstrap-diagnostic/unit-package-signatures"
printf 'unit package signature evidence: %s\n' "$work"

for order in caller-first callee-first; do
    inputs=("$fixtures/main.s" "$fixtures/relocated.s")
    if [ "$order" = callee-first ]; then
        inputs=("$fixtures/relocated.s" "$fixtures/main.s")
    fi
    "$seed" --compile-unit "$work/$order.ir" "${inputs[@]}"
    "$seed" --emit-bin "$work/$order.ir" "$work/$order"
    status=0
    "$work/$order" || status=$?
    test "$status" -eq 42
done

if "$seed" --compile-unit "$work/bad.ir" "$fixtures/bad.s" "$fixtures/relocated.s" >"$work/bad.log" 2>&1; then
    echo 'FAIL: package call accepted the wrong number of arguments' >&2
    exit 1
fi
grep -Fq 'expects 1' "$work/bad.log"
test ! -s "$work/bad.ir"
printf 'unit package signatures: PASS (declaration path, forward call, native behavior, arity rejection)\n'
