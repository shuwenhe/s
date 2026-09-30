#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage12/canonical-ownership-gate.txt"
RAW_STAGE11="${REPORT}.stage11.raw.$$"
RAW_STAGE12="${REPORT}.stage12.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_STAGE11" "$RAW_STAGE12" "$TMP_REPORT"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

write_s12_fail_report() {
    local contract=$1
    local reason=$2
    {
        echo "STAGE 12 - OWNERSHIP / MOVE / BORROW / NLL"
        echo "Scope: Stage 12 gate only; canonical MIR input boundary before ownership analysis"
        echo "Monomorphization/layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage12-ownership-gate"
        if [ "$contract" = "S12.2" ]; then
            echo "S12.1=PASS"
            echo "S12.1.evidence=$(proof_value S12.1.evidence "$RAW_STAGE12")"
            echo "S12.2=FAIL"
            echo "S12.2.reason=$reason"
        else
            echo "S12.1=FAIL"
            echo "S12.1.reason=$reason"
        fi
        echo "first-unmet-contract=$contract"
        echo "reason=$reason"
        echo "stage12-ownership=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    write_s12_fail_report "S12.1" "no executable compiler available to observe Stage11 MIR verification output"
    exit $?
fi

input="${S_STAGE12_PROOF_INPUT:-$SOURCE_ROOT/test/compiler/stage7_type_checking_basic.s}"

"$COMPILER" canonical-mir-verification-proof "$input" "$RAW_STAGE11" || true

if [ ! -f "$RAW_STAGE11" ] || [ "$(proof_value S11.1 "$RAW_STAGE11")" != "PASS" ]; then
    write_s12_fail_report "S12.1" "Stage11 canonical MIR verification was not closed"
    exit $?
fi

if [ "$(proof_value S11.1.input-authority "$RAW_STAGE11")" != "stage10-canonical-mir-output" ] ||
   [ "$(proof_value S11.1.mir-input-consumed "$RAW_STAGE11")" != "yes" ] ||
   [ "$(proof_value S11.1.mir-reconstruction "$RAW_STAGE11")" != "no" ]; then
    write_s12_fail_report "S12.1" "Stage11 did not expose a clean canonical MIR handoff for Stage12"
    exit $?
fi

if "$COMPILER" canonical-ownership-proof "$input" "$RAW_STAGE12" >/dev/null 2>&1; then
    if [ "$(proof_value S12.1 "$RAW_STAGE12")" = "PASS" ] &&
       [ "$(proof_value S12.1.input-authority "$RAW_STAGE12")" = "stage11-verified-canonical-mir" ] &&
       [ "$(proof_value S12.1.mir-input-consumed "$RAW_STAGE12")" = "yes" ] &&
       [ "$(proof_value S12.1.mir-reconstruction "$RAW_STAGE12")" = "no" ] &&
       [ -n "$(proof_value S12.1.evidence "$RAW_STAGE12")" ]; then
        write_s12_fail_report "S12.2" "no observable Stage 12 move analysis producer"
        exit $?
    fi
fi

write_s12_fail_report "S12.1" "no observable Stage 12 proof producer"
exit $?
