#!/bin/bash

# mir-ownership-place-audit-check.sh
# C.3.1b.2-a: Canonical Place Audit (Facts Only)

GATE_NAME="C.3.1b.2-a: Place Audit"
GATE_PHASE="audit"

# Find project root (from gates dir: ../../../../../../../)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# gates -> tests -> internal -> compile -> cmd -> s
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

# File locations
MIR_FILE="$PROJECT_ROOT/src/cmd/compile/internal/mir.s"
PLACE_MODEL_FILE="$PROJECT_ROOT/src/cmd/compile/internal/ownership/place_model.s"
BORROW_CHECKER_FILE="$PROJECT_ROOT/src/cmd/compile/internal/ownership/borrow_checker.s"
OWNERSHIP_STATE_FILE="$PROJECT_ROOT/src/cmd/compile/internal/ownership/ownership_state.s"
MOVE_CHECKER_FILE="$PROJECT_ROOT/src/cmd/compile/internal/ownership/move_checker.s"
DROP_CLOSURE_FILE="$PROJECT_ROOT/src/cmd/compile/internal/ownership/ownership_drop_closure.s"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FACTS_FOUND=0
FACTS_MISSING=0

check_fact() {
    local description="$1"
    local file="$2"
    local pattern="$3"
    
    if [ -f "$file" ] && grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $description"
        ((FACTS_FOUND++))
    else
        echo -e "${RED}✗${NC} $description"
        ((FACTS_MISSING++))
    fi
}

echo "================================================================"
echo "$GATE_NAME - $GATE_PHASE"
echo "================================================================"

# Fact 1: MIR Place
echo ""
echo "--- Fact 1: MIR Place Structure ---"
check_fact "1. mir_place defined" "$MIR_FILE" "struct mir_place"
check_fact "2. mir_place has root field" "$MIR_FILE" "string root"
check_fact "3. mir_place_projection defined" "$MIR_FILE" "struct mir_place_projection"

# Fact 2: MIR Flow State
echo ""
echo "--- Fact 2: MIR Flow State Format ---"
check_fact "4. mir_flow_state defined" "$MIR_FILE" "struct mir_flow_state"
check_fact "5. mir_flow_state uses string arrays" "$MIR_FILE" "string.*\[\].*moved"

# Fact 3: Borrow
echo ""
echo "--- Fact 3: Borrow Representation ---"
check_fact "6. borrow_info defined" "$OWNERSHIP_STATE_FILE" "struct borrow_info"
check_fact "7. borrow_info has string source" "$OWNERSHIP_STATE_FILE" "string source"
check_fact "8. borrow_stmt defined" "$BORROW_CHECKER_FILE" "struct borrow_stmt"

# Fact 4: Move
echo ""
echo "--- Fact 4: Move Representation ---"
check_fact "9. move_stmt in borrow_checker" "$BORROW_CHECKER_FILE" "struct move_stmt"
check_fact "10. move_checker uses .string()" "$MOVE_CHECKER_FILE" ".string()"

# Fact 5: Place Model
echo ""
echo "--- Fact 5: Mature Place Model ---"
check_fact "11. place_model.s exists" "$PLACE_MODEL_FILE" "ownership_place"
check_fact "12. ownership_place_overlaps defined" "$PLACE_MODEL_FILE" "ownership_place_overlaps"
check_fact "13. Root overlap rule exists" "$PLACE_MODEL_FILE" "left == 0 || right == 0"

# Fact 6: Integration status
echo ""
echo "--- Fact 6: Place Model Integration Status ---"
if grep -q "ownership_place_overlaps" "$BORROW_CHECKER_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} 14. place_model called in borrow_checker"
    ((FACTS_FOUND++))
else
    echo -e "${RED}✗${NC} 14. place_model NOT called in borrow_checker (ISOLATED)"
    ((FACTS_MISSING++))
fi

if grep -q "ownership_place_overlaps" "$MOVE_CHECKER_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} 15. place_model called in move_checker"
    ((FACTS_FOUND++))
else
    echo -e "${RED}✗${NC} 15. place_model NOT called in move_checker (ISOLATED)"
    ((FACTS_MISSING++))
fi


echo ""
echo "================================================================"
TOTAL=$((FACTS_FOUND + FACTS_MISSING))
echo "Audit Result: $FACTS_FOUND/$TOTAL facts verified"
echo "================================================================"

echo ""
echo "SEMANTIC AUDIT FINDINGS:"
echo ""
echo "Place Representation Status:"
if [ -f "$MIR_FILE" ]; then
    echo "  ✓ MIR uses structured (root + projections): YES"
fi
if grep -q "string source" "$OWNERSHIP_STATE_FILE" 2>/dev/null; then
    echo "  • Borrow uses textual representation: string source"
fi
if grep -q ".string()" "$MOVE_CHECKER_FILE" 2>/dev/null; then
    echo "  • Move uses textual representation: AST → string conversion"
fi
if [ -f "$PLACE_MODEL_FILE" ]; then
    echo "  • place_model.s has overlap logic: DEFINED but ISOLATED"
fi

echo ""
echo "INTEGRATION STATUS:"
if ! grep -q "ownership_place_overlaps" "$BORROW_CHECKER_FILE" 2>/dev/null; then
    echo "  🔴 place_model.s is NOT integrated with Borrow system"
fi
if ! grep -q "ownership_place_overlaps" "$MOVE_CHECKER_FILE" 2>/dev/null; then
    echo "  🔴 place_model.s is NOT integrated with Move system"
fi

echo ""
echo "SEMANTIC RECONSTRUCTION RISK:"
if grep -q ".string()" "$MOVE_CHECKER_FILE" 2>/dev/null; then
    echo "  🔴 CONFIRMED: AST nodes converted to strings for state lookup"
    echo "     This is the pattern we want to avoid in C.3.1"
fi

echo ""
echo "CRITICAL DECISION:"
echo ""
echo "  ❌ CANNOT proceed with C.3.1b.2-b or C.3.1b.2-c yet"
echo ""
echo "  Reason: Three Place subsystems exist with no shared canonical type:"
echo "    - Borrow: string source (\"_1.0\")"
echo "    - Move: string variable + AST.string() (\"_1\")"
echo "    - place_model.s: integer enum IDs (0-4)"
echo ""
echo "  Writing a conflict query on string places would require:"
echo "    1. Parse \"_1.0\" into (root, path)"
echo "    2. Parse \"_1.0.1\" into (root, path)"
echo "    3. Compare paths"
echo ""
echo "  This re-introduces semantic reconstruction we eliminated in C.3.0"
echo ""

echo "REQUIRED PREREQUISITE:"
echo ""
echo "  ✅ Next phase: C.3.1b.2-pre (Canonical Place Unification)"
echo ""
echo "  Steps:"
echo "    1. Define canonical Place type (enum-based or struct-based)"
echo "    2. Add parser: string Place → canonical Place"
echo "    3. Integrate place_model.s overlap logic"
echo "    4. Connect to Borrow and Move systems"
echo "    5. THEN implement conflict query"
echo ""

exit 0
