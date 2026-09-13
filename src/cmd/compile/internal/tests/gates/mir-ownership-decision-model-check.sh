#!/bin/bash
# Gate: mir-ownership-decision-model-check
# Purpose: Verify C.3.1a Decision Model type definitions are pure and uncontaminated
# Date: 2026-09-17
# Phase: C.3.1a (Type Vocabulary Only - No Logic)

# DO NOT use set -e so we can see all check results
# set -e

# Direct path to analysis.s
ANALYSIS_FILE="/Users/shuwen/shuwen/s/src/cmd/compile/internal/ownership/analysis.s"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================================"
echo "Gate: mir-ownership-decision-model-check"
echo "Phase: C.3.1a - Decision Model Type Verification"
echo "================================================================"

ANALYSIS_FILE="/Users/shuwen/shuwen/s/src/cmd/compile/internal/ownership/analysis.s"

if [ ! -f "$ANALYSIS_FILE" ]; then
    echo -e "${RED}FAIL${NC}: analysis.s not found at $ANALYSIS_FILE"
    exit 1
fi

PASS=true
CHECKS_PASSED=0
CHECKS_FAILED=0

# Helper function
check_requirement() {
    local name="$1"
    local condition="$2"
    
    if eval "$condition"; then
        echo -e "${GREEN}✓${NC} $name"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}✗${NC} $name"
        ((CHECKS_FAILED++))
        PASS=false
    fi
}

echo ""
echo "--- Structural Requirements ---"

# Check 1: ownership_decision struct exists
check_requirement \
    "ownership_decision struct defined" \
    "grep -q 'struct ownership_decision {' '$ANALYSIS_FILE'"

# Check 2: ownership_decision does NOT contain source_pos
check_requirement \
    "ownership_decision does NOT contain source_pos field" \
    "! grep -A 4 'struct ownership_decision {' '$ANALYSIS_FILE' | grep -v '^}' | grep -q 'source_pos'"

# Check 3: ownership_decision does NOT contain mir_point_id
check_requirement \
    "ownership_decision does NOT contain mir_point_id field" \
    "! grep -A 4 'struct ownership_decision {' '$ANALYSIS_FILE' | grep -v '^}' | grep -q 'mir_point_id'"

# Check 4: ownership_decision contains kind field
check_requirement \
    "ownership_decision contains kind field" \
    "grep -A 10 'struct ownership_decision {' '$ANALYSIS_FILE' | grep -q 'ownership_decision_kind'"

# Check 5: ownership_decision contains operation field
check_requirement \
    "ownership_decision contains operation field" \
    "grep -A 10 'struct ownership_decision {' '$ANALYSIS_FILE' | grep -q 'ownership_operation_kind'"

# Check 6: ownership_decision contains reason field (enum, not string)
check_requirement \
    "ownership_decision contains reason field (enum)" \
    "grep -A 10 'struct ownership_decision {' '$ANALYSIS_FILE' | grep -q 'ownership_decision_reason'"

echo ""
echo "--- OLD Observation Type ---"

# Check 7: old_ownership_observation exists
check_requirement \
    "old_ownership_observation struct defined" \
    "grep -q 'struct old_ownership_observation {' '$ANALYSIS_FILE'"

# Check 8: old_ownership_observation contains decision field
check_requirement \
    "old_ownership_observation contains decision field" \
    "grep -A 5 'struct old_ownership_observation {' '$ANALYSIS_FILE' | grep -q 'ownership_decision'"

# Check 9: old_ownership_observation contains source_pos field
check_requirement \
    "old_ownership_observation contains source_pos field" \
    "grep -A 5 'struct old_ownership_observation {' '$ANALYSIS_FILE' | grep -q 'source_pos'"

echo ""
echo "--- SHADOW Observation Type ---"

# Check 10: shadow_ownership_observation exists
check_requirement \
    "shadow_ownership_observation struct defined" \
    "grep -q 'struct shadow_ownership_observation {' '$ANALYSIS_FILE'"

# Check 11: shadow_ownership_observation contains decision field
check_requirement \
    "shadow_ownership_observation contains decision field" \
    "grep -A 5 'struct shadow_ownership_observation {' '$ANALYSIS_FILE' | grep -q 'ownership_decision'"

# Check 12: shadow_ownership_observation contains mir_point_id field
check_requirement \
    "shadow_ownership_observation contains mir_point_id field" \
    "grep -A 5 'struct shadow_ownership_observation {' '$ANALYSIS_FILE' | grep -q 'mir_point_id'"

echo ""
echo "--- Decision Diff Type ---"

# Check 13: ownership_decision_diff exists
check_requirement \
    "ownership_decision_diff struct defined" \
    "grep -q 'struct ownership_decision_diff {' '$ANALYSIS_FILE'"

# Check 14: ownership_decision_diff references both observation types
check_requirement \
    "ownership_decision_diff contains old observation" \
    "grep -A 10 'struct ownership_decision_diff {' '$ANALYSIS_FILE' | grep -q 'old_ownership_observation'"

check_requirement \
    "ownership_decision_diff contains shadow observation" \
    "grep -A 10 'struct ownership_decision_diff {' '$ANALYSIS_FILE' | grep -q 'shadow_ownership_observation'"

check_requirement \
    "ownership_decision_diff contains match field" \
    "grep -A 10 'struct ownership_decision_diff {' '$ANALYSIS_FILE' | grep -q 'bool.*match'"

echo ""
echo "--- Type Validation (Enums) ---"

# Check 16: ownership_decision_kind enum exists
check_requirement \
    "ownership_decision_kind enum defined" \
    "grep -q 'enum ownership_decision_kind' '$ANALYSIS_FILE'"

# Check 17: ownership_operation_kind enum exists
check_requirement \
    "ownership_operation_kind enum defined" \
    "grep -q 'enum ownership_operation_kind' '$ANALYSIS_FILE'"

# Check 18: ownership_decision_reason enum exists
check_requirement \
    "ownership_decision_reason enum defined" \
    "grep -q 'enum ownership_decision_reason' '$ANALYSIS_FILE'"

echo ""
echo "--- Purity Checks (No Logic Contamination) ---"

# Check 19: No compiler_fail in type definitions
check_requirement \
    "No compiler_fail() in type section" \
    "! grep -A 50 'C.3.1a: Decision Model' '$ANALYSIS_FILE' | grep -q 'compiler_fail'"

# Check 20: No solver calls in type definitions
check_requirement \
    "No solver calls in type section" \
    "! grep -A 50 'C.3.1a: Decision Model' '$ANALYSIS_FILE' | grep -q 'analyze_ownership_liveness'"

# Check 21: No conflict checking logic (not in enum values)
check_requirement \
    "No conflict checking logic in type section" \
    "! grep -A 50 'C.3.1a: Decision Model' '$ANALYSIS_FILE' | grep -v '^enum' | grep -v 'live_loan_conflict' | grep -q 'check.*conflict\|analyze.*conflict\|test.*conflict'"

echo ""
echo "================================================================"
echo "Summary: $CHECKS_PASSED passed, $CHECKS_FAILED failed"
echo "================================================================"

if $PASS; then
    echo -e "${GREEN}✓ PASS${NC}: C.3.1a Decision Model type definitions are structurally correct"
    echo ""
    echo "Next: Do NOT implement query functions yet."
    echo "      Proceed to C.3.1b.1 only after this gate passes consistently."
    echo ""
    exit 0
else
    echo -e "${RED}✗ FAIL${NC}: Decision Model type requirements not met"
    echo ""
    echo "Failed checks: $CHECKS_FAILED"
    echo ""
    exit 1
fi
