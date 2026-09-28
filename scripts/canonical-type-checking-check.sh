#!/bin/bash

################################################################################
# canonical-type-checking-check.sh
#
# Stage 7-only gate: Type Checking.
#
# This gate does not prove CanonicalTypeRef, layout, MIR, ABI, or codegen. Its
# first responsibility is deterministic attribution: if Stage 7 is not closed,
# report the first unmet S7.x contract in S7.1 -> S7.8 order.
################################################################################

set -euo pipefail

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage7/type-checking-gate.txt"
RAW_REPORT="${REPORT}.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_REPORT" "$TMP_REPORT"' EXIT HUP INT TERM

contract_title() {
    case "$1" in
        S7.1) echo "Input Boundary" ;;
        S7.2) echo "Type Environment Authority" ;;
        S7.3) echo "Declaration Type Facts" ;;
        S7.4) echo "Expression Type Facts" ;;
        S7.5) echo "Compatibility Semantics" ;;
        S7.6) echo "Type Error Rejection" ;;
        S7.7) echo "No Re-Resolution Or Identity Reconstruction" ;;
        S7.8) echo "Output Boundary" ;;
        *) echo "Unknown Contract" ;;
    esac
}

contract_number() {
    case "$1" in
        S7.1) echo 1 ;;
        S7.2) echo 2 ;;
        S7.3) echo 3 ;;
        S7.4) echo 4 ;;
        S7.5) echo 5 ;;
        S7.6) echo 6 ;;
        S7.7) echo 7 ;;
        S7.8) echo 8 ;;
        *) echo 1 ;;
    esac
}

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

contains_forbidden_later_stage_claim() {
    local value=$1
    printf '%s\n' "$value" | grep -Eq 'CanonicalTypeRef|MIR|layout|ABI|codegen|S8\.'
}

write_report() {
    local proof_source=$1
    local proof_file=$2
    local first_unmet="NONE"
    local first_reason="NONE"
    local result="PASS"
    local stage7="CLOSED"
    local contract status evidence reason title

    {
        echo "STAGE 7 - TYPE CHECKING"
        echo "Scope: Stage 7 only; stop at type reasoning boundary"
        echo "CanonicalTypeRef success is NOT required."
        echo "Lowering/MIR/backend success is NOT required."
        echo "Layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=$proof_source"
        echo "proof-report=$proof_file"
    } > "$TMP_REPORT"

    for contract in S7.1 S7.2 S7.3 S7.4 S7.5 S7.6 S7.7 S7.8; do
        title=$(contract_title "$contract")
        status=$(proof_value "$contract" "$proof_file")
        evidence=$(proof_value "${contract}.evidence" "$proof_file")
        reason=$(proof_value "${contract}.reason" "$proof_file")

        if [ "$status" = "PASS" ] && [ -n "$evidence" ]; then
            if contains_forbidden_later_stage_claim "$evidence"; then
                status="FAIL"
                reason="forbidden later-stage claim in proof for $contract $title"
            else
                echo "$contract $title=PASS" >> "$TMP_REPORT"
                echo "$contract.evidence=$evidence" >> "$TMP_REPORT"
                continue
            fi
        fi

        if [ -z "$status" ]; then
            status="FAIL"
            reason="no observable proof for $contract $title"
        elif [ "$status" = "PASS" ] && [ -z "$evidence" ]; then
            status="FAIL"
            reason="PASS lacks reproducible evidence for $contract $title"
        elif [ -z "$reason" ]; then
            reason="contract did not pass: $contract $title"
        fi

        echo "$contract $title=$status" >> "$TMP_REPORT"
        echo "$contract.reason=$reason" >> "$TMP_REPORT"

        if [ "$first_unmet" = "NONE" ]; then
            first_unmet=$contract
            first_reason=$reason
            result="FAIL"
            stage7="NOT_CLOSED"
        fi
    done

    {
        echo "first-unmet-contract=$first_unmet"
        echo "reason=$first_reason"
        echo "stage7-type-checking=$stage7"
        echo "result=$result"
    } >> "$TMP_REPORT"

    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"

    if [ "$result" = "PASS" ]; then
        return 0
    fi
    return "$(contract_number "$first_unmet")"
}

if [ "${S_STAGE7_ALLOW_MOCK_PROOF:-0}" = "1" ] && [ -n "${S_STAGE7_PROOF_REPORT:-}" ]; then
    if [ ! -f "$S_STAGE7_PROOF_REPORT" ]; then
        echo "canonical-type-checking-check: mock proof report not found: $S_STAGE7_PROOF_REPORT" >&2
        exit 2
    fi
    write_report "mock" "$S_STAGE7_PROOF_REPORT"
    exit $?
fi

if [ ! -x "$COMPILER" ]; then
    {
        echo "S7.1=FAIL"
        echo "S7.1.reason=no executable compiler available to observe canonical Type Checking input boundary"
    } > "$RAW_REPORT"
    write_report "compiler-missing" "$RAW_REPORT"
    exit $?
fi

help_status=0
help_output=$($COMPILER help 2>&1) || help_status=$?
if ! printf '%s\n' "$help_output" | grep -Fq 'type-checking-proof'; then
    help_status=0
    help_output=$($COMPILER --help 2>&1) || help_status=$?
fi

if printf '%s\n' "$help_output" | grep -Fq 'type-checking-proof'; then
    proof_status=0
    proof_input="${S_STAGE7_PROOF_INPUT:-$SOURCE_ROOT/test/compiler/stage7_type_checking_basic.s}"
    "$COMPILER" type-checking-proof "$proof_input" "$RAW_REPORT" || proof_status=$?
    if [ "$proof_status" -ne 0 ] || [ ! -f "$RAW_REPORT" ]; then
        {
            echo "S7.1=FAIL"
            echo "S7.1.reason=compiler exposes Stage 7 proof command but did not produce a proof report"
        } > "$RAW_REPORT"
    fi
    write_report "compiler-type-checking-proof" "$RAW_REPORT"
    exit $?
fi

{
    echo "S7.1=FAIL"
    echo "S7.1.reason=no observable Stage 7 proof producer; compiler does not expose type-checking-proof"
} > "$RAW_REPORT"
write_report "not-observable" "$RAW_REPORT"
exit $?
