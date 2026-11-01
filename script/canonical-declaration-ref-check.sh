#!/bin/bash

################################################################################
# canonical-declaration-ref-check.sh
#
# Stage 6-only gate: DeclarationRef.
#
# This gate does not prove type checking, CanonicalTypeRef, layout, MIR, or
# codegen. Its first responsibility is deterministic attribution: if Stage 6 is
# not closed, report the first unmet S6.x contract in S6.1 -> S6.8 order.
################################################################################

set -euo pipefail

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage6/declaration-ref-gate.txt"
RAW_REPORT="${REPORT}.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_REPORT" "$TMP_REPORT"' EXIT HUP INT TERM

contract_title() {
    case "$1" in
        S6.1) echo "Input Boundary" ;;
        S6.2) echo "Canonical Producer" ;;
        S6.3) echo "Identity Authority" ;;
        S6.4) echo "Stable Identity" ;;
        S6.5) echo "Uniqueness" ;;
        S6.6) echo "Equality Semantics" ;;
        S6.7) echo "No Re-Resolution" ;;
        S6.8) echo "Output Boundary" ;;
        *) echo "Unknown Contract" ;;
    esac
}

contract_number() {
    case "$1" in
        S6.1) echo 1 ;;
        S6.2) echo 2 ;;
        S6.3) echo 3 ;;
        S6.4) echo 4 ;;
        S6.5) echo 5 ;;
        S6.6) echo 6 ;;
        S6.7) echo 7 ;;
        S6.8) echo 8 ;;
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
    printf '%s\n' "$value" | grep -Eq 'Type Checking|CanonicalTypeRef|MIR|layout|ABI|codegen'
}

write_report() {
    local proof_source=$1
    local proof_file=$2
    local first_unmet="NONE"
    local first_reason="NONE"
    local result="PASS"
    local stage6="CLOSED"
    local contract status evidence reason title

    {
        echo "STAGE 6 - DECLARATIONREF"
        echo "Scope: Stage 6 only; stop at canonical declaration identity boundary"
        echo "Type Checking success is NOT required."
        echo "CanonicalTypeRef success is NOT required."
        echo "Lowering/MIR/backend success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=$proof_source"
        echo "proof-report=$proof_file"
    } > "$TMP_REPORT"

    for contract in S6.1 S6.2 S6.3 S6.4 S6.5 S6.6 S6.7 S6.8; do
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
            stage6="NOT_CLOSED"
        fi
    done

    {
        echo "first-unmet-contract=$first_unmet"
        echo "reason=$first_reason"
        echo "stage6-declaration-ref=$stage6"
        echo "result=$result"
    } >> "$TMP_REPORT"

    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"

    if [ "$result" = "PASS" ]; then
        return 0
    fi
    return "$(contract_number "$first_unmet")"
}

if [ "${S_STAGE6_ALLOW_MOCK_PROOF:-0}" = "1" ] && [ -n "${S_STAGE6_PROOF_REPORT:-}" ]; then
    if [ ! -f "$S_STAGE6_PROOF_REPORT" ]; then
        echo "canonical-declaration-ref-check: mock proof report not found: $S_STAGE6_PROOF_REPORT" >&2
        exit 2
    fi
    write_report "mock" "$S_STAGE6_PROOF_REPORT"
    exit $?
fi

if [ ! -x "$COMPILER" ]; then
    {
        echo "S6.1=FAIL"
        echo "S6.1.reason=no executable compiler available to observe canonical DeclarationRef input boundary"
    } > "$RAW_REPORT"
    write_report "compiler-missing" "$RAW_REPORT"
    exit $?
fi

help_status=0
help_output=$($COMPILER help 2>&1) || help_status=$?
if ! printf '%s\n' "$help_output" | grep -Fq 'declaration-ref-proof'; then
    help_status=0
    help_output=$($COMPILER --help 2>&1) || help_status=$?
fi

if printf '%s\n' "$help_output" | grep -Fq 'declaration-ref-proof'; then
    proof_status=0
    proof_input="${S_STAGE6_PROOF_INPUT:-$SOURCE_ROOT/test/compiler/stage6_declaration_ref_uniqueness_a.s}"
    S_STAGE6_UNIQUENESS_OTHER_INPUT="${S_STAGE6_UNIQUENESS_OTHER_INPUT:-$SOURCE_ROOT/test/compiler/stage6_declaration_ref_uniqueness_b.s}" "$COMPILER" declaration-ref-proof "$proof_input" "$RAW_REPORT" || proof_status=$?
    if [ "$proof_status" -ne 0 ] || [ ! -f "$RAW_REPORT" ]; then
        {
            echo "S6.1=FAIL"
            echo "S6.1.reason=compiler exposes Stage 6 proof command but did not produce a proof report"
        } > "$RAW_REPORT"
    fi
    write_report "compiler-declaration-ref-proof" "$RAW_REPORT"
    exit $?
fi

{
    echo "S6.1=FAIL"
    echo "S6.1.reason=no observable Stage 6 proof producer; compiler does not expose declaration-ref-proof"
} > "$RAW_REPORT"
write_report "not-observable" "$RAW_REPORT"
exit $?
