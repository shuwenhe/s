#!/bin/bash

################################################################################
# canonical-semantic-check.sh
#
# Stage 9-only gate: Semantic Analysis consumer boundary.
#
# This first gate intentionally does not prove semantic analysis correctness. It
# only asks whether the real Stage 9 entry consumes the Stage 8 CanonicalTypeRef
# output carrier without reconstructing Stage 8 authority.
################################################################################

set -euo pipefail

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage9/canonical-semantic-gate.txt"
RAW_STAGE8="${REPORT}.stage8.raw.$$"
RAW_STAGE9="${REPORT}.stage9.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_STAGE8" "$RAW_STAGE9" "$TMP_REPORT"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

write_s9_fail_report() {
    local contract=$1
    local title=$2
    local reason=$3
    {
        echo "STAGE 9 - SEMANTIC ANALYSIS"
        echo "Scope: Stage 9 only; consumer audit for Stage 8 canonical output"
        echo "MIR/layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage9-canonical-consumer-audit"
        if [ "$contract" = "S9.1" ]; then
            echo "S9.1 Canonical Input Consumption=FAIL"
            echo "S9.1.reason=$reason"
        else
            echo "S9.1 Canonical Input Consumption=PASS"
            echo "S9.1.evidence=$(proof_value S9.1.evidence "$RAW_STAGE9")"
            echo "$contract $title=FAIL"
            echo "$contract.reason=$reason"
        fi
        echo "first-unmet-contract=$contract"
        echo "reason=$reason"
        echo "stage9-semantic-analysis=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    write_s9_fail_report "S9.1" "Canonical Input Consumption" "no executable compiler available to observe Stage8 output carrier"
    exit $?
fi

stage8_input="${S_STAGE8_PROOF_INPUT:-$SOURCE_ROOT/test/compiler/stage7_type_checking_basic.s}"
S_STAGE7_NEGATIVE_PROOF_INPUT="${S_STAGE7_NEGATIVE_PROOF_INPUT:-$SOURCE_ROOT/test/compiler/stage7_type_checking_type_error.s}" \
S_STAGE8_UNIQUENESS_OTHER_INPUT="${S_STAGE8_UNIQUENESS_OTHER_INPUT:-$SOURCE_ROOT/test/compiler/stage8_canonical_type_ref_box.s}" \
    "$COMPILER" canonical-type-ref-proof "$stage8_input" "$RAW_STAGE8" || true

if [ ! -f "$RAW_STAGE8" ] || ! grep -qx 'S8.8.output-carrier=compiler-stage8-canonical-type-ref-output' "$RAW_STAGE8"; then
    write_s9_fail_report "S9.1" "Canonical Input Consumption" "Stage8 canonical output carrier was not observable"
    exit $?
fi

if [ ! -f "$RAW_STAGE8" ] || ! grep -qx 'S8.8.canonical-type-ref-readable=yes' "$RAW_STAGE8"; then
    write_s9_fail_report "S9.1" "Canonical Input Consumption" "Stage8 canonical output carrier was not readable"
    exit $?
fi

"$COMPILER" canonical-semantic-proof "$stage8_input" "$RAW_STAGE9" || true

if [ ! -f "$RAW_STAGE9" ] || [ "$(proof_value S9.1 "$RAW_STAGE9")" != "PASS" ]; then
    write_s9_fail_report "S9.1" "Canonical Input Consumption" "no observable Stage9 consumer of Stage8 canonical output"
    exit $?
fi

if [ -z "$(proof_value S9.1.evidence "$RAW_STAGE9")" ]; then
    write_s9_fail_report "S9.1" "Canonical Input Consumption" "PASS lacks reproducible evidence for S9.1 Canonical Input Consumption"
    exit $?
fi

# Phase 1: Check S9.2 Semantic Authority
if [ "$(proof_value S9.2 "$RAW_STAGE9")" = "PASS" ]; then
    # S9.2 passed - write success report
    {
        echo "STAGE 9 - SEMANTIC ANALYSIS"
        echo "Scope: Stage 9 only; consumer audit for Stage 8 canonical output"
        echo "MIR/layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage9-canonical-consumer-audit"
        echo "S9.1 Canonical Input Consumption=PASS"
        echo "S9.1.evidence=$(proof_value S9.1.evidence "$RAW_STAGE9")"
        echo "S9.2 Semantic Authority=PASS"
        echo "S9.2.evidence=$(proof_value S9.2.evidence "$RAW_STAGE9")"
        echo "first-unmet-contract=NONE"
        echo "reason=NONE"
        echo "stage9-semantic-analysis=CLOSED"
        echo "result=PASS"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    exit 0
fi

write_s9_fail_report "S9.2" "Semantic Authority" "no observable proof for S9.2 Semantic Authority"
exit $?
