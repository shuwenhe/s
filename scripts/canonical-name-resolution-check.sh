#!/bin/bash

################################################################################
# canonical-name-resolution-check.sh
#
# Stage 5-only gate: Name / Import Resolution.
#
# This gate does not prove DeclarationRef, type checking, layout, MIR, or codegen.
# Its first responsibility is deterministic attribution: if Stage 5 is not closed,
# report the first unmet S5.x contract in S5.1 -> S5.9 order.
################################################################################

set -euo pipefail

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage5/name-resolution-gate.txt"
RAW_REPORT="${REPORT}.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_REPORT" "$TMP_REPORT"' EXIT HUP INT TERM

contract_title() {
    case "$1" in
        S5.1) echo "Input Authority" ;;
        S5.2) echo "Package Identity" ;;
        S5.3) echo "Import Registration" ;;
        S5.4) echo "Declaration Index" ;;
        S5.5) echo "Unqualified Lookup" ;;
        S5.6) echo "Qualified Lookup" ;;
        S5.7) echo "Ambiguity Rejection" ;;
        S5.8) echo "Unresolved-name Rejection" ;;
        S5.9) echo "Output Boundary" ;;
        *) echo "Unknown Contract" ;;
    esac
}

contract_number() {
    case "$1" in
        S5.1) echo 1 ;;
        S5.2) echo 2 ;;
        S5.3) echo 3 ;;
        S5.4) echo 4 ;;
        S5.5) echo 5 ;;
        S5.6) echo 6 ;;
        S5.7) echo 7 ;;
        S5.8) echo 8 ;;
        S5.9) echo 9 ;;
        *) echo 1 ;;
    esac
}

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

write_report() {
    local proof_source=$1
    local proof_file=$2
    local first_unmet="NONE"
    local first_reason="NONE"
    local result="PASS"
    local stage5="CLOSED"
    local contract status evidence reason title

    {
        echo "STAGE 5 - NAME / IMPORT RESOLUTION"
        echo "Scope: Stage 5 only; stop at resolved declaration candidate boundary"
        echo "DeclarationRef success is NOT required."
        echo "Type Checking success is NOT required."
        echo "CanonicalTypeRef success is NOT required."
        echo "Lowering/MIR/backend success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=$proof_source"
        echo "proof-report=$proof_file"
    } > "$TMP_REPORT"

    for contract in S5.1 S5.2 S5.3 S5.4 S5.5 S5.6 S5.7 S5.8 S5.9; do
        title=$(contract_title "$contract")
        status=$(proof_value "$contract" "$proof_file")
        evidence=$(proof_value "${contract}.evidence" "$proof_file")
        reason=$(proof_value "${contract}.reason" "$proof_file")

        if [ "$status" = "PASS" ] && [ -n "$evidence" ]; then
            echo "$contract $title=PASS" >> "$TMP_REPORT"
            echo "$contract.evidence=$evidence" >> "$TMP_REPORT"
            continue
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
            stage5="NOT_CLOSED"
        fi
    done

    {
        echo "first-unmet-contract=$first_unmet"
        echo "reason=$first_reason"
        echo "stage5-name-resolution=$stage5"
        echo "result=$result"
    } >> "$TMP_REPORT"

    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"

    if [ "$result" = "PASS" ]; then
        return 0
    fi
    return "$(contract_number "$first_unmet")"
}

if [ "${S_STAGE5_ALLOW_MOCK_PROOF:-0}" = "1" ] && [ -n "${S_STAGE5_PROOF_REPORT:-}" ]; then
    if [ ! -f "$S_STAGE5_PROOF_REPORT" ]; then
        echo "canonical-name-resolution-check: mock proof report not found: $S_STAGE5_PROOF_REPORT" >&2
        exit 2
    fi
    write_report "mock" "$S_STAGE5_PROOF_REPORT"
    exit $?
fi

if [ ! -x "$COMPILER" ]; then
    {
        echo "S5.1=FAIL"
        echo "S5.1.reason=no executable compiler available to observe canonical AST input authority"
    } > "$RAW_REPORT"
    write_report "compiler-missing" "$RAW_REPORT"
    exit $?
fi

help_status=0
help_output=$($COMPILER help 2>&1) || help_status=$?
if ! printf '%s\n' "$help_output" | grep -Fq 'stage5-name-resolution-proof'; then
    help_status=0
    help_output=$($COMPILER --help 2>&1) || help_status=$?
fi

if printf '%s\n' "$help_output" | grep -Fq 'stage5-name-resolution-proof'; then
    proof_status=0
    proof_input="${S_STAGE5_PROOF_INPUT:-$SOURCE_ROOT/test/compiler/stage5_import_registration.s}"
    "$COMPILER" stage5-name-resolution-proof "$proof_input" "$RAW_REPORT" || proof_status=$?
    if [ "$proof_status" -ne 0 ] || [ ! -f "$RAW_REPORT" ]; then
        {
            echo "S5.1=FAIL"
            echo "S5.1.reason=compiler exposes Stage 5 proof command but did not produce a proof report"
        } > "$RAW_REPORT"
    fi
    write_report "compiler-stage5-name-resolution-proof" "$RAW_REPORT"
    exit $?
fi

{
    echo "S5.1=FAIL"
    echo "S5.1.reason=no observable Stage 5 proof producer; compiler does not expose stage5-name-resolution-proof"
} > "$RAW_REPORT"
write_report "not-observable" "$RAW_REPORT"
exit $?
