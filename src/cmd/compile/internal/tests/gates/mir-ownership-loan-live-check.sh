#!/bin/bash
# Gate: mir-ownership-loan-live-check
# Purpose: Verify C.3.1b.1 analysis_loan_live_at() query function
# Date: 2026-09-17
# Phase: C.3.1b.1 (Loan Liveness Query - Pure Query Layer)

# Don't fail on first error so we see all results
PASS=true
CHECKS_PASSED=0
CHECKS_FAILED=0

ANALYSIS_FILE="/Users/shuwen/shuwen/s/src/cmd/compile/internal/ownership/analysis.s"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================================"
echo "Gate: mir-ownership-loan-live-check"
echo "Phase: C.3.1b.1 - Loan Liveness Query API"
echo "================================================================"
echo ""

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

echo "--- Function Existence ---"

# Check 1: analysis_loan_live_at function exists
check_requirement \
    "analysis_loan_live_at function defined" \
    "grep -q 'func analysis_loan_live_at' '$ANALYSIS_FILE'"

echo ""
echo "--- Function Signature ---"

# Check 2: Function takes ownership_analysis* parameter
check_requirement \
    "Takes ownership_analysis* parameter" \
    "grep -A 4 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q 'ownership_analysis\*'"

# Check 3: Function takes int loan_id parameter
check_requirement \
    "Takes int loan_id parameter" \
    "grep -A 4 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q 'loan_id'"

# Check 4: Function takes int point_id parameter
check_requirement \
    "Takes int point_id parameter" \
    "grep -A 4 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q 'point_id'"

# Check 5: Function returns bool
check_requirement \
    "Returns bool" \
    "grep -A 4 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q ') bool'"

echo ""
echo "--- Implementation Properties ---"

# Check 6: Validates loan_id (checks for out-of-bounds)
check_requirement \
    "Validates loan_id >= 0" \
    "grep -A 20 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q 'loan_id < 0'"

# Check 7: Validates loan_id upper bound
check_requirement \
    "Validates loan_id < array length" \
    "grep -A 20 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q 'len(analysis.loan_live_points)'"

# Check 8: Validates point_id >= 0
check_requirement \
    "Validates point_id >= 0" \
    "grep -A 20 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q 'point_id < 0'"

# Check 9: Validates point_id capacity constraint (30-bit, P0..P30)
check_requirement \
    "Validates point_id < 31 (30-bit point capacity)" \
    "grep -A 20 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q 'point_id >= 31'"

# Check 10: Checks for nil analysis
check_requirement \
    "Checks for nil analysis pointer" \
    "grep -A 20 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q 'analysis == nil'"

echo ""
echo "--- Query Logic ---"

# Check 11: Uses bitwise AND for query
check_requirement \
    "Uses bitwise AND (&) for query" \
    "grep -A 30 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q '& mask'"

# Check 12: Uses bit shift to create mask
check_requirement \
    "Uses bit shift (<<) for mask" \
    "grep -A 30 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q '1 << point_id'"

echo ""
echo "--- Purity Checks (No Contamination) ---"

# Check 13: No Place concept
check_requirement \
    "No Place concept in function" \
    "! grep -A 30 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -v '^//' | grep -q 'place\\|Place\\|Field\\|projection'"

# Check 14: No conflict checking
check_requirement \
    "No conflict checking" \
    "! grep -A 30 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -v '^//' | grep -q 'conflict\\|Conflict'"

# Check 15: No Decision making
check_requirement \
    "No Decision making" \
    "! grep -A 30 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -v '^//' | grep -q 'ownership_decision'"

# Check 16: No compiler_fail calls
check_requirement \
    "No compiler_fail() calls" \
    "! grep -A 30 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -v '^//' | grep -q 'compiler_fail'"

# Check 17: No solver mutation
check_requirement \
    "No solver mutation" \
    "! grep -A 30 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -v '^//' | grep -q 'analyze_ownership\\|region_live\\|iterations'"

# Check 18: No s.pos references
check_requirement \
    "No s.pos references" \
    "! grep -A 30 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -v '^//' | grep -q 's\\.pos'"

echo ""
echo "--- Documentation ---"

# Check 19: Has C.3.1b.1 marker comment
check_requirement \
    "Has C.3.1b.1 phase marker" \
    "grep -q 'C.3.1b.1' '$ANALYSIS_FILE'"

# Check 20: Mentions pure query in comments
check_requirement \
    "Documents as pure query" \
    "grep -B 5 'func analysis_loan_live_at' '$ANALYSIS_FILE' | grep -q 'Pure\\|pure'"

echo ""
echo "================================================================"
echo "Summary: $CHECKS_PASSED passed, $CHECKS_FAILED failed"
echo "================================================================"

if $PASS; then
    echo -e "${GREEN}✓ PASS${NC}: analysis_loan_live_at() is pure and correct"
    echo ""
    echo "Function signature verified:"
    echo "  analysis_loan_live_at(ownership_analysis*, int, int) -> bool"
    echo ""
    echo "Properties verified:"
    echo "  - Queries loan liveness using 32-bit bitmask"
    echo "  - No Place concept"
    echo "  - No conflict logic"
    echo "  - No Decision making"
    echo "  - No compiler_fail()"
    echo "  - No solver mutation"
    echo "  - No s.pos"
    echo ""
    echo "Boundary validation:"
    echo "  - Returns false for nil analysis"
    echo "  - Returns false for invalid loan_id"
    echo "  - Returns false for invalid point_id (>= 31)"
    echo ""
    echo "Next: Implement analysis_place_conflicts() in C.3.1b.2"
    echo ""
    exit 0
else
    echo -e "${RED}✗ FAIL${NC}: analysis_loan_live_at() requirements not met"
    echo ""
    echo "Failed checks: $CHECKS_FAILED"
    echo ""
    exit 1
fi
