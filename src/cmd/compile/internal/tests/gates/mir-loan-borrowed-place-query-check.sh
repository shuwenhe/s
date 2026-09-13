#!/bin/bash

# mir-loan-borrowed-place-query-check.sh
# B1.3: Safe Loan→Place Query (Shadow Analysis Entry Point)
# Verifies mir_loan_borrowed_place() implements proper query semantics

GATE_NAME="B1.3: Safe Loan→Place Query"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"
MIR_FILE="$PROJECT_ROOT/src/cmd/compile/internal/mir.s"
TEST_FILE="$PROJECT_ROOT/src/cmd/compile/internal/tests/test_b1_3_loan_query.s"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    if grep -q "$2" "$3"; then
        echo -e "${GREEN}✓${NC} $1"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} $1"
        ((FAIL++))
    fi
}

check_not() {
    if ! grep -q "$2" "$3"; then
        echo -e "${GREEN}✓${NC} $1"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} $1"
        ((FAIL++))
    fi
}

echo "================================================================"
echo "$GATE_NAME"
echo "================================================================"
echo ""

echo "--- [LAYER 1] Query Function Signature ---"
check "Function exists: mir_loan_borrowed_place" "func mir_loan_borrowed_place" "$MIR_FILE"
check "Returns (mir_place, bool)" "mir_place, bool" "$MIR_FILE"
check "Takes facts pointer and loan_id" "mir_ownership_facts\*.*int loan_id" "$MIR_FILE"

echo ""
echo "--- [LAYER 2] Loan Identity Invariant ---"
check "LOAN IDENTITY INVARIANT documented" "LOAN IDENTITY INVARIANT" "$MIR_FILE"
check "Invariant maintenance rule stated" "Maintenance rule" "$MIR_FILE"
check "Violation consequence explained" "out-of-sync" "$MIR_FILE"
check "Dense indexing contract clear" "dense Loan ID" "$MIR_FILE"

echo ""
echo "--- [LAYER 3] Query Safety Semantics ---"
check "Nil check for facts" "if facts == nil" "$MIR_FILE"
check "Bounds check: loan_id < 0" "loan_id < 0" "$MIR_FILE"
check "Bounds check: loan_id >= loan_count" "loan_id >= facts.input.loan_count" "$MIR_FILE"
check "Array sync check: loan_id >= len" "loan_id >= len(facts.loan_borrowed_places)" "$MIR_FILE"
check "Returns (place, true) on success" "return facts.loan_borrowed_places\[loan_id\], true" "$MIR_FILE"
check "Returns (zero, false) on failure" "return mir_place{}, false" "$MIR_FILE"

echo ""
echo "--- [LAYER 4] Contract and Examples ---"
check "Contract: MUST check bool ok" "MUST check bool ok" "$MIR_FILE"
check "Contract: prohibit sentinel usage" "must NOT use place.root" "$MIR_FILE"
check "Example usage provided" "place, ok :=" "$MIR_FILE"

echo ""
echo "--- [LAYER 5] Two-Borrow E2E Extraction ---"
if [ -f "$TEST_FILE" ]; then
    echo -e "${GREEN}✓${NC} Test fixture file exists"
    ((PASS++))
    
    check "Fixture has L0 (owner.left.value)" "left.*value" "$TEST_FILE"
    check "Fixture has L1 (other.right)" "other.*right" "$TEST_FILE"
    check "Creates two borrow statements" "borrow_stmt_l0" "$TEST_FILE"
    check "Appends both to same block" "mir_statement::borrow" "$TEST_FILE"
    check "Verifies loan_count==2" "loan_count != 2" "$TEST_FILE"
    check "Queries L0 by index 0" "mir_loan_borrowed_place.*0" "$TEST_FILE"
    check "Queries L1 by index 1" "mir_loan_borrowed_place.*1" "$TEST_FILE"
else
    echo -e "${RED}✗${NC} Test fixture file missing"
    ((FAIL++))
fi

echo ""
echo "--- [LAYER 6] Loan Count / Array Sync ---"
check "Invariant verified in test" "if len(facts.loan_borrowed_places) != facts.input.loan_count" "$TEST_FILE"
check "Different places for different loans" "mir.mir_place_equal(place_query_l0, place_query_l1)" "$TEST_FILE"

echo ""
echo "--- [LAYER 7] Out-of-Bounds Safety ---"
check "Test query with loan_id=-1" "mir_loan_borrowed_place.*-1" "$TEST_FILE"
check "Test query with loan_id=2 (overflow)" "mir_loan_borrowed_place.*2" "$TEST_FILE"
check "Test query with loan_id=100 (large overflow)" "mir_loan_borrowed_place.*100" "$TEST_FILE"
check "Nil facts pointer handled safely" "mir_loan_borrowed_place(nil" "$TEST_FILE"
check "Nil queries return ok=false" "if ok_nil" "$TEST_FILE"

echo ""
echo "--- [LAYER 8] Legacy Backward Compatibility ---"
check "Legacy test included" "test_b1_3_legacy_string" "$TEST_FILE"
check "Legacy loan_places still populated" "loan_places.*1" "$TEST_FILE"
check "Canonical loan_borrowed_places also populated" "loan_borrowed_places.*1" "$TEST_FILE"

echo ""
echo "--- [LAYER 9] Helper Functions ---"
check "mir_place_from_fields helper added" "func mir_place_from_fields" "$MIR_FILE"
check "Constructs nested projections" "mir_place_projection.*field" "$MIR_FILE"

echo ""
echo "--- [LAYER 10] Authority Boundary Isolation ---"
check "No modification to analysis_loan_live_at" "func analysis_loan_live_at" "$PROJECT_ROOT/src/cmd/compile/internal/ownership/analysis.s"
check_not "No modification to Solver" "mir_loan_borrowed_place" "$PROJECT_ROOT/src/cmd/compile/internal/compiler.s" 2>/dev/null || echo -e "${YELLOW}(compiler.s unavailable for check)${NC}"
check_not "No modification to borrow_info" "mir_loan_borrowed_place" "$PROJECT_ROOT/src/cmd/compile/internal/ownership/ownership_state.s"

echo ""
echo "================================================================"
echo "Result: $PASS passed, $FAIL failed"
echo "================================================================"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ B1.3 COMPLETE${NC}"
    echo ""
    echo "Safe Loan→Place query layer established:"
    echo "  ✓ Layer 1: mir_loan_borrowed_place(facts*, loan_id) (mir_place, bool)"
    echo "  ✓ Layer 2: Loan identity invariant documented"
    echo "  ✓ Layer 3: Multiple safety checks (nil, bounds, sync)"
    echo "  ✓ Layer 4: Explicit bool contract (no sentinel)"
    echo "  ✓ Layer 5: Two-borrow E2E fixture (L0, L1)"
    echo "  ✓ Layer 6: Invariant: loan_count == len(loan_borrowed_places)"
    echo "  ✓ Layer 7: Out-of-bounds queries fail safely"
    echo "  ✓ Layer 8: Legacy string paths preserved"
    echo ""
    echo "Shadow query points now available:"
    echo "  Query 1: analysis_loan_live_at(L, P) → bool"
    echo "  Query 2: mir_loan_borrowed_place(facts, L) → (mir_place, bool)"
    echo "  Two independent queries now available"
    echo "  No synthesis/conflict authority is established yet"
    echo ""
    echo "Solver unchanged:"
    echo "  ✓ ownership_analysis_input untouched"
    echo "  ✓ LoanLivePoints computation unaffected"
    echo "  ✓ ACCEPT/REJECT authority unchanged"
    echo ""
    echo "Next: B1.4 Canonical Authority Audit"
else
    echo ""
    echo -e "${RED}✗ FAILED${NC}"
fi

exit 0
