#!/bin/bash
set -euo pipefail

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage11/canonical-mir-verification-gate.txt"
RAW_STAGE10="${REPORT}.stage10.raw.$$"
RAW_STAGE11="${REPORT}.stage11.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_STAGE10" "$RAW_STAGE11" "$TMP_REPORT"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

write_s11_fail_report() {
    local contract=$1
    local reason=$2
    {
        echo "STAGE 11 - MIR VERIFICATION"
        echo "Scope: Stage 11 only; consumer audit for Stage 10 canonical MIR output"
        echo "Ownership/layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage11-mir-verification-consumer-audit"
        echo "S11.1 Canonical MIR Input Consumption=FAIL"
        echo "S11.1.reason=$reason"
        echo "first-unmet-contract=$contract"
        echo "reason=$reason"
        echo "stage11-mir-verification=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    write_s11_fail_report "S11.1" "no executable compiler available to observe Stage10 MIR output"
    exit $?
fi

input="${S_STAGE11_PROOF_INPUT:-$SOURCE_ROOT/test/compiler/stage7_type_checking_basic.s}"

"$COMPILER" canonical-lowering-proof "$input" "$RAW_STAGE10" || true

if [ ! -f "$RAW_STAGE10" ] || [ "$(proof_value S10.1 "$RAW_STAGE10")" != "PASS" ]; then
    write_s11_fail_report "S11.1" "Stage10 canonical semantic input consumption was not closed"
    exit $?
fi

if [ ! -f "$RAW_STAGE10" ] || [ "$(proof_value S10.2 "$RAW_STAGE10")" != "PASS" ]; then
    write_s11_fail_report "S11.1" "Stage10 MIR output boundary was not closed"
    exit $?
fi

if "$COMPILER" canonical-mir-verification-proof "$input" "$RAW_STAGE11" >/dev/null 2>&1; then
    if [ "$(proof_value S11.1 "$RAW_STAGE11")" = "PASS" ] &&
       [ "$(proof_value S11.1.input-authority "$RAW_STAGE11")" = "stage10-canonical-mir-output" ] &&
       [ "$(proof_value S11.1.mir-input-consumed "$RAW_STAGE11")" = "yes" ] &&
       [ "$(proof_value S11.1.mir-reconstruction "$RAW_STAGE11")" = "no" ] &&
       [ -n "$(proof_value S11.1.evidence "$RAW_STAGE11")" ]; then
        {
            echo "STAGE 11 - MIR VERIFICATION"
            echo "Scope: Stage 11 only; consumer audit for Stage 10 canonical MIR output"
            echo "Ownership/layout/ABI/codegen success is NOT required."
            echo "compiler=$COMPILER"
            echo "proof-source=stage11-mir-verification-consumer-audit"
            echo "S11.1 Canonical MIR Input Consumption=PASS"
            echo "S11.1.evidence=$(proof_value S11.1.evidence "$RAW_STAGE11")"
            echo "first-unmet-contract=NONE"
            echo "reason=NONE"
            echo "stage11-mir-verification=CLOSED"
            echo "result=PASS"
        } > "$TMP_REPORT"
        mv "$TMP_REPORT" "$REPORT"
        cat "$REPORT"
        exit 0
    fi
fi

write_s11_fail_report "S11.1" "no observable Stage11 verifier consumer of Stage10 canonical MIR output"
exit $?
