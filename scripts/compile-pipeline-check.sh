#!/bin/bash

################################################################################
# compile-pipeline-check.sh
#
# S COMPILER CANONICAL PIPELINE DRIVER
# Frontier-Driven Development Model
#
# Core Discipline:
#   1. Execute stages in strict sequence (1 -> 2 -> ...)
#   2. Separate execution status from proof status
#   3. Only substantive PASS/PROVEN advances the proven frontier
#   4. SKIP, PLACEHOLDER, and FAIL are not proof
#
# Usage:
#   ./scripts/compile-pipeline-check.sh
#   OR via makefile:
#   make compile-pipeline-check
#
# Output:
#   - Stage execution status and proof status
#   - First unproven required stage
#   - Current semantic blocker
#   - Exit code: 0 only if every required stage is proven
#
################################################################################

set -euo pipefail

SOURCE_ROOT="${S_SOURCE_ROOT:-.}"
REPORT_DIR="${SOURCE_ROOT}/.bootstrap/pipeline"
REPORT_FILE="${REPORT_DIR}/compile-pipeline-check.txt"
TMP_DIR="${REPORT_DIR}/tmp"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$REPORT_DIR" "$TMP_DIR"

# stage_num:stage_name:gate_script:gate_target:required
# Required means this stage must have a substantive proof before the pipeline can
# claim completion. Early closure stages that do not yet have standalone gates are
# tracked as UNPROVEN but do not block the current semantic frontier.
declare -a PIPELINE=(
    "1:Source:source-closure-check:N/A:optional"
    "2:Lexer:lexer-closure-check:N/A:optional"
    "3:Parser:canonical-parser-closure-check:bin/s_seed:required"
    "4:AST:ast-validation-check:N/A:optional"
    "5:Name/Import Resolution:canonical-name-resolution-check:bin/s_compiler:required"
    "6:DeclarationRef:canonical-declaration-ref-check:bin/s_compiler:required"
    "7:Type Checking:canonical-type-checking-check:bin/s_compiler:required"
    "8:CanonicalTypeRef:canonical-type-ref-check:bin/s_compiler:required"
    "9:Semantic Analysis:canonical-semantic-check:bin/s_compiler:required"
    "10:Lowering->MIR:canonical-lowering-check:bin/s_compiler:required"
    "11:MIR Verification:canonical-mir-verification-check:bin/s_compiler:required"
    "12:Ownership/Move/Borrow/NLL:canonical-ownership-check:bin/s_compiler:required"
    "13:Monomorphization:canonical-monomorphization-check:bin/s_compiler:required"
    "14:Optimization:canonical-optimization-check:bin/s_compiler:required"
    "15:Layout:canonical-layout-check:bin/s_compiler:required"
    "16:ABI:canonical-abi-check:bin/s_compiler:required"
    "17:Instruction Selection/Codegen:canonical-codegen-check:bin/s_compiler:required"
    "18:Register Allocation:canonical-regalloc-check:bin/s_compiler:required"
    "19:Machine Code:canonical-machine-code-check:bin/s_compiler:required"
    "20:Object/ELF Emission:canonical-object-emission-check:bin/s_compiler:required"
    "21:Linking:canonical-linking-check:bin/s_compiler:required"
    "22:Executable:canonical-executable-check:bin/s_compiler:required"
)

declare -a STATUS_LOG=()
FIRST_UNPROVEN_STAGE=0
FIRST_UNPROVEN_NAME=""
FIRST_UNPROVEN_REASON=""
FIRST_FAILED_STAGE=0
PROVEN_FRONTIER=0
EXECUTION_FRONTIER=0

print_header() {
    :
}

color_execution_status() {
    case "$1" in
        PASS) echo -e "${GREEN}PASS${NC}" ;;
        FAIL) echo -e "${RED}FAIL${NC}" ;;
        PLACEHOLDER) echo -e "${YELLOW}PLACEHOLDER${NC}" ;;
        SKIP|NOT_RUN) echo -e "${YELLOW}$1${NC}" ;;
        *) echo "$1" ;;
    esac
}

record_unproven_if_required() {
    local stage_num=$1
    local stage_name=$2
    local requirement=$3
    local reason=$4

    if [[ "$requirement" == "required" && $FIRST_UNPROVEN_STAGE -eq 0 ]]; then
        FIRST_UNPROVEN_STAGE=$stage_num
        FIRST_UNPROVEN_NAME=$stage_name
        FIRST_UNPROVEN_REASON=$reason
    fi
}

stage_output_has_placeholder_marker() {
    local output_file=$1

    grep -Eq 'PENDING_IMPLEMENTATION|result[[:space:]]*=[[:space:]]*PENDING|Full integration pending|placeholder|TODO:|NOT YET RE-VERIFIED' "$output_file"
}

run_stage() {
    local stage_num=$1
    local stage_name=$2
    local gate_script=$3
    local gate_target=$4
    local requirement=$5
    local gate_path="${SOURCE_ROOT}/scripts/${gate_script}.sh"
    local stage_output="${TMP_DIR}/stage-${stage_num}.out"
    local execution_status=""
    local proof_status=""
    local reason=""

    : > "$stage_output"

    if [[ ! -f "$gate_path" ]]; then
        if ! make "$gate_script" > "$stage_output" 2>&1; then
            execution_status="SKIP"
            proof_status="UNPROVEN"
            reason="no gate implementation"
            printf "[%02d] %-35s %-13s %s\n" \
                "$stage_num" "$stage_name" "$(color_execution_status "$execution_status")" "$proof_status"
            STATUS_LOG+=("$stage_num:$stage_name:$execution_status:$proof_status:$requirement:$reason")
            record_unproven_if_required "$stage_num" "$stage_name" "$requirement" "$reason"
            return 0
        fi
    else
        if ! "$gate_path" "$SOURCE_ROOT" > "$stage_output" 2>&1; then
            execution_status="FAIL"
            proof_status="FAILED"
            reason="gate $gate_script failed"
            FIRST_FAILED_STAGE=$stage_num
            printf "[%02d] %-35s %-13s %s\n" \
                "$stage_num" "$stage_name" "$(color_execution_status "$execution_status")" "$proof_status"
            STATUS_LOG+=("$stage_num:$stage_name:$execution_status:$proof_status:$requirement:$reason")
            record_unproven_if_required "$stage_num" "$stage_name" "$requirement" "$reason"
            return 1
        fi
    fi

    if stage_output_has_placeholder_marker "$stage_output"; then
        execution_status="PLACEHOLDER"
        proof_status="UNPROVEN"
        reason="gate executed but reported pending implementation"
        printf "[%02d] %-35s %-13s %s\n" \
            "$stage_num" "$stage_name" "$(color_execution_status "$execution_status")" "$proof_status"
        STATUS_LOG+=("$stage_num:$stage_name:$execution_status:$proof_status:$requirement:$reason")
        record_unproven_if_required "$stage_num" "$stage_name" "$requirement" "$reason"
        return 0
    fi

    execution_status="PASS"
    proof_status="PROVEN"
    reason="substantive gate passed"
    printf "[%02d] %-35s %-13s %s\n" \
        "$stage_num" "$stage_name" "$(color_execution_status "$execution_status")" "$proof_status"
    STATUS_LOG+=("$stage_num:$stage_name:$execution_status:$proof_status:$requirement:$reason")

    if [[ "$requirement" == "required" && $FIRST_UNPROVEN_STAGE -eq 0 ]]; then
        PROVEN_FRONTIER=$stage_num
    fi

    return 0
}

print_header

for stage_entry in "${PIPELINE[@]}"; do
    IFS=':' read -r stage_num stage_name gate_script gate_target requirement <<< "$stage_entry"
    EXECUTION_FRONTIER=$stage_num

    if [[ $FIRST_FAILED_STAGE -gt 0 ]]; then
        printf "[%02d] %-35s %-13s %s\n" "$stage_num" "$stage_name" "$(color_execution_status NOT_RUN)" "UNPROVEN"
        STATUS_LOG+=("$stage_num:$stage_name:NOT_RUN:UNPROVEN:$requirement:previous required gate failed")
        record_unproven_if_required "$stage_num" "$stage_name" "$requirement" "previous required gate failed"
        continue
    fi

    run_stage "$stage_num" "$stage_name" "$gate_script" "$gate_target" "$requirement" || true
done

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

if [[ $FIRST_UNPROVEN_STAGE -eq 0 ]]; then
    echo -e "${GREEN}PIPELINE COMPLETE = YES${NC}"
    echo "All required stages are PROVEN"
    EXIT_CODE=0
else
    echo -e "${RED}PIPELINE COMPLETE = NO${NC}"
    echo "FIRST UNPROVEN REQUIRED STAGE = $FIRST_UNPROVEN_STAGE"
    echo "CURRENT BLOCKER = Stage $FIRST_UNPROVEN_STAGE $FIRST_UNPROVEN_NAME"
    echo "Reason: $FIRST_UNPROVEN_REASON"
    EXIT_CODE=$FIRST_UNPROVEN_STAGE
fi

echo "EXECUTION FRONTIER = STAGE $EXECUTION_FRONTIER"
echo "PROVEN FRONTIER = STAGE $PROVEN_FRONTIER"
echo ""

cat > "$REPORT_FILE" << EOF
S COMPILER CANONICAL PIPELINE CHECK
====================================
Date: $(date)
Pipeline complete: $([[ $FIRST_UNPROVEN_STAGE -eq 0 ]] && echo YES || echo NO)
Execution frontier: Stage $EXECUTION_FRONTIER
Proven frontier: Stage $PROVEN_FRONTIER
First unproven required stage: $([[ $FIRST_UNPROVEN_STAGE -eq 0 ]] && echo NONE || echo "Stage $FIRST_UNPROVEN_STAGE $FIRST_UNPROVEN_NAME")
Current blocker: $([[ $FIRST_UNPROVEN_STAGE -eq 0 ]] && echo NONE || echo "Stage $FIRST_UNPROVEN_STAGE $FIRST_UNPROVEN_NAME")

STAGE STATUS:
EOF

for entry in "${STATUS_LOG[@]}"; do
    IFS=':' read -r stage_num stage_name execution_status proof_status requirement reason <<< "$entry"
    printf "[%02d] %-30s %-12s %-9s %-8s %s\n" \
        "$stage_num" "$stage_name" "$execution_status" "$proof_status" "$requirement" "$reason" >> "$REPORT_FILE"
done

echo "Report written to: $REPORT_FILE"
echo ""

exit "$EXIT_CODE"
