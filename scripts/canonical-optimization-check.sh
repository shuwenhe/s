#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage14/canonical-optimization-gate.txt"
RAW_STAGE14="${REPORT}.stage14.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_STAGE14" "$TMP_REPORT"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

write_s14_fail_report() {
    local contract=$1
    local reason=$2
    if [ "$contract" = "S14.2" ] && [ -z "$reason" ]; then
        reason="no observable Stage 14 optimization producer/artifact/consumer handoff"
    fi
    {
        echo "STAGE 14 - OPTIMIZATION"
        echo "Scope: Stage 14 gate only; canonical monomorphized input before layout/ABI/codegen"
        echo "Layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage14-optimization-gate"
        if [ "$contract" = "S14.1" ]; then
            echo "S14.1=FAIL"
            echo "S14.1.reason=$reason"
        elif [ "$contract" = "S14.2" ]; then
            echo "S14.1=PASS"
            echo "S14.1.contract=$(proof_value S14.1.contract "$RAW_STAGE14")"
            echo "S14.1.input-authority=$(proof_value S14.1.input-authority "$RAW_STAGE14")"
            echo "S14.1.production-full-mir-producer=$(proof_value S14.1.production-full-mir-producer "$RAW_STAGE14")"
            echo "S14.1.production-full-mir-artifact=$(proof_value S14.1.production-full-mir-artifact "$RAW_STAGE14")"
            echo "S14.1.production-optimization-consumer=$(proof_value S14.1.production-optimization-consumer "$RAW_STAGE14")"
            echo "S14.1.proof-visible-representation=$(proof_value S14.1.proof-visible-representation "$RAW_STAGE14")"
            echo "S14.1.proof-summary-is-production-mir=$(proof_value S14.1.proof-summary-is-production-mir "$RAW_STAGE14")"
            echo "S14.1.reconstruction=$(proof_value S14.1.reconstruction "$RAW_STAGE14")"
            echo "S14.1.evidence=$(proof_value S14.1.evidence "$RAW_STAGE14")"
            echo "S14.2=FAIL"
            echo "S14.2.reason=$reason"
        fi
        echo "first-unmet-contract=$(proof_value first-unmet-contract "$RAW_STAGE14")"
        echo "stage14-optimization=$(proof_value stage14-optimization "$RAW_STAGE14")"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

write_s14_pass_report() {
    {
        echo "STAGE 14 - OPTIMIZATION"
        echo "Scope: Stage 14 gate only; canonical monomorphized input before layout/ABI/codegen"
        echo "Layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage14-optimization-gate"
        echo "S14.1=PASS"
        echo "S14.1.contract=$(proof_value S14.1.contract "$RAW_STAGE14")"
        echo "S14.1.input-authority=$(proof_value S14.1.input-authority "$RAW_STAGE14")"
        echo "S14.1.production-full-mir-producer=$(proof_value S14.1.production-full-mir-producer "$RAW_STAGE14")"
        echo "S14.1.production-full-mir-artifact=$(proof_value S14.1.production-full-mir-artifact "$RAW_STAGE14")"
        echo "S14.1.production-optimization-consumer=$(proof_value S14.1.production-optimization-consumer "$RAW_STAGE14")"
        echo "S14.1.proof-visible-representation=$(proof_value S14.1.proof-visible-representation "$RAW_STAGE14")"
        echo "S14.1.proof-summary-is-production-mir=$(proof_value S14.1.proof-summary-is-production-mir "$RAW_STAGE14")"
        echo "S14.1.reconstruction=$(proof_value S14.1.reconstruction "$RAW_STAGE14")"
        echo "S14.1.evidence=$(proof_value S14.1.evidence "$RAW_STAGE14")"
        echo "S14.2=PASS"
        echo "S14.2.contract=$(proof_value S14.2.contract "$RAW_STAGE14")"
        echo "S14.2.producer=$(proof_value S14.2.producer "$RAW_STAGE14")"
        echo "S14.2.data-structure=$(proof_value S14.2.data-structure "$RAW_STAGE14")"
        echo "S14.2.output-artifact=$(proof_value S14.2.output-artifact "$RAW_STAGE14")"
        echo "S14.2.consumer=$(proof_value S14.2.consumer "$RAW_STAGE14")"
        echo "S14.2.evidence=$(proof_value S14.2.evidence "$RAW_STAGE14")"
        echo "stage14-optimization=$(proof_value stage14-optimization "$RAW_STAGE14")"
        echo "result=PASS"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 0
}

if [ ! -x "$COMPILER" ]; then
    write_s14_fail_report "S14.1" "compiler not found or not executable: $COMPILER"
    exit $?
fi

RAW_STAGE14_TMP="${RAW_STAGE14}.tmp"
TEST_FILE="${SOURCE_ROOT}/test/compiler/stage12_move_semantics_real.s"
if [ ! -f "$TEST_FILE" ]; then
    write_s14_fail_report "S14.1" "test input file not found: $TEST_FILE"
    exit $?
fi

"$COMPILER" canonical-optimization-proof "$TEST_FILE" "$RAW_STAGE14_TMP" 2>/dev/null || true
mv "$RAW_STAGE14_TMP" "$RAW_STAGE14"

if [ "$(proof_value S14.1 "$RAW_STAGE14")" = "PASS" ] &&
   [ "$(proof_value S14.1.contract "$RAW_STAGE14")" = "production-full-mir-input-authority" ] &&
   [ "$(proof_value S14.1.input-authority "$RAW_STAGE14")" = "production-full-mir-authority" ] &&
   [ "$(proof_value S14.1.production-full-mir-producer "$RAW_STAGE14")" = "compile.internal.ir.lower.lower_main_to_mir" ] &&
   [ "$(proof_value S14.1.production-full-mir-artifact "$RAW_STAGE14")" = "mir_graph" ] &&
   [ -n "$(proof_value S14.1.production-optimization-consumer "$RAW_STAGE14")" ] &&
   [ "$(proof_value S14.1.proof-visible-representation "$RAW_STAGE14")" = "stage12_mir_graph-summary" ] &&
   [ "$(proof_value S14.1.proof-summary-is-production-mir "$RAW_STAGE14")" = "no" ] &&
   [ "$(proof_value S14.1.reconstruction "$RAW_STAGE14")" = "no" ] &&
   [ -n "$(proof_value S14.1.evidence "$RAW_STAGE14")" ]; then
    if [ "$(proof_value S14.2 "$RAW_STAGE14")" = "PASS" ] &&
       [ "$(proof_value S14.2.contract "$RAW_STAGE14")" = "optimization-producer-artifact-handoff" ] &&
       [ -n "$(proof_value S14.2.producer "$RAW_STAGE14")" ] &&
       [ -n "$(proof_value S14.2.data-structure "$RAW_STAGE14")" ] &&
       [ -n "$(proof_value S14.2.output-artifact "$RAW_STAGE14")" ] &&
       [ -n "$(proof_value S14.2.consumer "$RAW_STAGE14")" ] &&
       [ -n "$(proof_value S14.2.evidence "$RAW_STAGE14")" ] &&
       [ "$(proof_value stage14-optimization "$RAW_STAGE14")" = "CLOSED" ]; then
        write_s14_pass_report
        exit $?
    fi
    if [ "$(proof_value first-unmet-contract "$RAW_STAGE14")" = "S14.2" ]; then
        write_s14_fail_report "S14.2" "$(proof_value S14.2.reason "$RAW_STAGE14")"
        exit $?
    fi
fi

if [ "$(proof_value first-unmet-contract "$RAW_STAGE14")" = "S14.1" ]; then
    write_s14_fail_report "S14.1" "$(proof_value S14.1.reason "$RAW_STAGE14")"
    exit $?
fi

write_s14_fail_report "S14.1" "no observable Stage 14 proof producer"
exit $?
