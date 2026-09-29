#!/bin/bash

################################################################################
# canonical-lowering-check.sh
#
# Stage 10-only gate: Lowering -> MIR.
#
# This first gate intentionally does not prove MIR correctness. It only asks
# whether a real production MIR lowering path consumes the Stage 9 semantic
# result boundary without reconstructing earlier frontend authority.
################################################################################

set -euo pipefail

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage10/canonical-lowering-gate.txt"
RAW_STAGE9="${REPORT}.stage9.raw.$$"
RAW_STAGE10="${REPORT}.stage10.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_STAGE9" "$RAW_STAGE10" "$TMP_REPORT"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

write_s10_fail_report() {
    local contract=$1
    local title=$2
    local reason=$3
    {
        echo "STAGE 10 - LOWERING -> MIR"
        echo "Scope: Stage 10 only; consumer audit for Stage 9 semantic output"
        echo "MIR verification/ownership/layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage10-mir-lowering-consumer-audit"
        echo "S10.1 Canonical Semantic Input Consumption=FAIL"
        echo "S10.1.reason=$reason"
        echo "first-unmet-contract=$contract"
        echo "reason=$reason"
        echo "stage10-lowering-mir=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    write_s10_fail_report "S10.1" "Canonical Semantic Input Consumption" "no executable compiler available to observe Stage9 semantic output"
    exit $?
fi

input="${S_STAGE10_PROOF_INPUT:-$SOURCE_ROOT/test/compiler/stage7_type_checking_basic.s}"

"$COMPILER" canonical-semantic-proof "$input" "$RAW_STAGE9" || true

if [ ! -f "$RAW_STAGE9" ] || [ "$(proof_value S9.1 "$RAW_STAGE9")" != "PASS" ]; then
    write_s10_fail_report "S10.1" "Canonical Semantic Input Consumption" "Stage9 canonical input consumption was not closed"
    exit $?
fi

if [ ! -f "$RAW_STAGE9" ] || [ "$(proof_value S9.2 "$RAW_STAGE9")" != "PASS" ]; then
    write_s10_fail_report "S10.1" "Canonical Semantic Input Consumption" "Stage9 semantic authority was not closed"
    exit $?
fi

if "$COMPILER" canonical-lowering-proof "$input" "$RAW_STAGE10" >/dev/null 2>&1; then
    if [ "$(proof_value S10.1 "$RAW_STAGE10")" = "PASS" ] &&
       [ "$(proof_value S10.1.input-authority "$RAW_STAGE10")" = "stage9-semantic-result" ] &&
       [ "$(proof_value S10.1.semantic-input-consumed "$RAW_STAGE10")" = "yes" ] &&
       [ "$(proof_value S10.1.semantic-reconstruction "$RAW_STAGE10")" = "no" ] &&
       [ -n "$(proof_value S10.1.evidence "$RAW_STAGE10")" ]; then
        {
            echo "STAGE 10 - LOWERING -> MIR"
            echo "Scope: Stage 10 only; consumer audit for Stage 9 semantic output"
            echo "MIR verification/ownership/layout/ABI/codegen success is NOT required."
            echo "compiler=$COMPILER"
            echo "proof-source=stage10-mir-lowering-consumer-audit"
            echo "S10.1 Canonical Semantic Input Consumption=PASS"
            echo "S10.1.evidence=$(proof_value S10.1.evidence "$RAW_STAGE10")"
            echo "first-unmet-contract=NONE"
            echo "reason=NONE"
            echo "stage10-lowering-mir=CLOSED"
            echo "result=PASS"
        } > "$TMP_REPORT"
        mv "$TMP_REPORT" "$REPORT"
        cat "$REPORT"
        exit 0
    fi
fi

write_s10_fail_report "S10.1" "Canonical Semantic Input Consumption" "no observable Stage10 MIR lowering consumer of Stage9 semantic_result"
exit $?
