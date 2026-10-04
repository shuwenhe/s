#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage13/canonical-monomorphization-gate.txt"
RAW_STAGE13="${REPORT}.stage13.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_STAGE13" "$TMP_REPORT"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

write_s13_fail_report() {
    local contract=$1
    local reason=$2
    if [ "$contract" = "S13.2" ] && [ -z "$reason" ]; then
        reason="no observable Stage 13 generic type resolution facts producer"
    fi
    {
        echo "STAGE 13 - MONOMORPHIZATION"
        echo "Scope: Stage 13 gate only; canonical ownership facts input before monomorphization"
        echo "Layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage13-monomorphization-gate"
        if [ "$contract" = "S13.1" ]; then
            echo "S13.1=FAIL"
            echo "S13.1.reason=$reason"
        elif [ "$contract" = "S13.2" ]; then
            echo "S13.1=PASS"
            echo "S13.1.contract=$(proof_value S13.1.contract "$RAW_STAGE13")"
            echo "S13.1.input-authority=$(proof_value S13.1.input-authority "$RAW_STAGE13")"
            echo "S13.1.ownership-facts-consumed=$(proof_value S13.1.ownership-facts-consumed "$RAW_STAGE13")"
            echo "S13.1.mir-reconstruction=$(proof_value S13.1.mir-reconstruction "$RAW_STAGE13")"
            echo "S13.1.evidence=$(proof_value S13.1.evidence "$RAW_STAGE13")"
            echo "S13.2=FAIL"
            echo "S13.2.reason=$reason"
        fi
        echo "first-unmet-contract=$(proof_value first-unmet-contract "$RAW_STAGE13")"
        echo "stage13-monomorphization=$(proof_value stage13-monomorphization "$RAW_STAGE13")"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

if [ ! -x "$COMPILER" ]; then
    write_s13_fail_report "S13.1" "compiler not found or not executable: $COMPILER"
    exit $?
fi

RAW_STAGE13_TMP="${RAW_STAGE13}.tmp"
TEST_FILE="${SOURCE_ROOT}/test/compiler/stage12_move_semantics_real.s"
if [ ! -f "$TEST_FILE" ]; then
    write_s13_fail_report "S13.1" "test input file not found: $TEST_FILE"
    exit $?
fi

"$COMPILER" canonical-monomorphization-proof "$TEST_FILE" "$RAW_STAGE13_TMP" 2>/dev/null || true
mv "$RAW_STAGE13_TMP" "$RAW_STAGE13"

if [ "$(proof_value S13.1 "$RAW_STAGE13")" = "PASS" ] &&
   [ "$(proof_value S13.1.contract "$RAW_STAGE13")" = "input-boundary" ] &&
   [ "$(proof_value S13.1.input-authority "$RAW_STAGE13")" = "stage12-ownership-facts" ] &&
   [ "$(proof_value S13.1.ownership-facts-consumed "$RAW_STAGE13")" = "yes" ] &&
   [ "$(proof_value S13.1.mir-reconstruction "$RAW_STAGE13")" = "no" ] &&
   [ -n "$(proof_value S13.1.evidence "$RAW_STAGE13")" ]; then
    if [ "$(proof_value first-unmet-contract "$RAW_STAGE13")" = "S13.2" ]; then
        write_s13_fail_report "S13.2" "$(proof_value S13.2.reason "$RAW_STAGE13")"
        exit $?
    fi
fi

if [ "$(proof_value first-unmet-contract "$RAW_STAGE13")" = "S13.1" ]; then
    write_s13_fail_report "S13.1" "$(proof_value S13.1.reason "$RAW_STAGE13")"
    exit $?
fi

write_s13_fail_report "S13.1" "no observable Stage 13 proof producer"
exit $?
