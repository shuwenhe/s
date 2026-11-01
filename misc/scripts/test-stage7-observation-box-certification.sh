#!/bin/sh

################################################################################
# test-stage7-observation-box-certification.sh
#
# Task A directed certification regression:
# Verify the Stage 7 certification/observation surface can observe a legal
# non-int semantic type (box) from a function's OWN declaration + return
# expression, independent of main's return expression.
#
# Authority: the real Type Checker populates per-function observation; the
# proof only reads it. No proof-side recomputation.
################################################################################

set -eu

SOURCE_ROOT="${1:-.}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
FIXTURE="${SOURCE_ROOT}/test/compiler/stage7_observation_box.s"
OUT="/tmp/stage7_observation_box_cert.txt"

if [ ! -x "$COMPILER" ]; then
    echo "SKIP: compiler not available"
    exit 0
fi

"$COMPILER" type-facts-observation-proof "$FIXTURE" "$OUT" 2>/dev/null || {
    echo "FAIL: observation proof did not run"
    exit 1
}

fail=0

grep -q "observation-authority=real-type-checker" "$OUT" || { echo "FAIL: missing real-type-checker authority"; fail=1; }
grep -q "function.0.name=helper" "$OUT" || { echo "FAIL: helper not observed as function 0"; fail=1; }
grep -q "function.0.declared-return-type=box" "$OUT" || { echo "FAIL: helper declared return type not box"; fail=1; }
grep -q "function.0.observed-return-expression-type=box" "$OUT" || { echo "FAIL: helper return expression type not box"; fail=1; }
grep -q "function.0.compatibility-result=compatible" "$OUT" || { echo "FAIL: helper compatibility not compatible"; fail=1; }
grep -q "function.0.declaration-ref=canonical-declaration-identity:function:" "$OUT" || { echo "FAIL: helper missing canonical DeclarationRef"; fail=1; }

# Guard: observation must not claim later-stage authority
if grep -Eq "CanonicalTypeRef|canonical-type-ref|MIR|layout|ABI|codegen|S8\." "$OUT"; then
    echo "FAIL: observation leaks later-stage authority"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: Stage 7 certification surface observes helper() box (declared=box, expr=box, compatible) from real Type Checker"
    exit 0
fi
exit 1
