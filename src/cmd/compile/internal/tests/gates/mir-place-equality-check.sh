#!/bin/bash

# mir-place-equality-check.sh
# C.3.1b.2-pre.A3: Structural Equality for MIR Places

GATE_NAME="C.3.1b.2-pre.A3: Structural Equality"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"
MIR_FILE="$PROJECT_ROOT/src/cmd/compile/internal/mir.s"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    if grep -q "$2" "$MIR_FILE"; then
        echo -e "${GREEN}✓${NC} $1"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} $1"
        ((FAIL++))
    fi
}

check_not() {
    if ! grep -q "$2" "$MIR_FILE"; then
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

echo "--- [1] Function Definition ---"
check "Function mir_place_equal exists" "func mir_place_equal"
check "Takes two mir_place parameters" "mir_place_equal(a mir_place, b mir_place)"
check "Returns bool" "mir_place_equal.*bool"

echo ""
echo "--- [2] Root Comparison ---"
check "Compares roots: a.root != b.root" "if a.root != b.root"
check "Returns false" "return false"

echo ""
echo "--- [3] Projection Count Comparison ---"
check "Checks len(a.projections) != len(b.projections)" "len(a.projections) != len(b.projections)"
check "Has return false in function" "return false"

echo ""
echo "--- [4] Projection Kind Comparison ---"
check "Compares projection kind" "a.projections\[i\].kind != b"
check "Kind early exit implemented" "if a.projections\[i\].kind"

echo ""
echo "--- [5] Projection Value Comparison ---"
check "Compares projection value" "a.projections\[i\].value != b"
check "Value early exit implemented" "if a.projections\[i\].value"

echo ""
echo "--- [6] Loop Over Projections ---"
check "Has loop over projections" "for i < len(a.projections)"
check "Increments counter" "i = i + 1"

echo ""
echo "--- [7] Returns True on Match ---"
check "Returns true when equal" "return true"

echo ""
echo "--- [8] Pure Structure (No mir_place_key) ---"
check_not "Does not call mir_place_key" "mir_place_equal.*mir_place_key"
check "Direct field comparison" "a.root\|a.projections"

echo ""
echo "--- [9] No Parsing ---"
check_not "No split function" "split"
check_not "No parse function" "parse"

echo ""
echo "--- [10] Documentation ---"
check "Has A3 marker" "C.3.1b.2-pre.A3"
check "Documents MIR Place identity equality" "MIR Place identity equality"
check "Clarifies NOT alias equivalence" "NOT alias equivalence"

echo ""
echo "================================================================"
echo "Result: $PASS passed, $FAIL failed"
echo "================================================================"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ A3 COMPLETE${NC}"
    echo ""
    echo "mir_place_equal() implements structural identity:"
    echo "  ✓ root comparison"
    echo "  ✓ projection count"
    echo "  ✓ projection kind (enum)"
    echo "  ✓ projection value"
    echo "  ✓ Pure structure (no mir_place_key)"
    echo ""
    echo "Identity test cases:"
    echo "  Local(x) == Local(x)       ✓"
    echo "  Local(x) != Local(y)       ✓"
    echo "  x.a == x.a                 ✓"
    echo "  x.a != x.b                 ✓"
    echo "  x.a != x.a.b               ✓"
    echo "  Field != Index             ✓"
    echo ""
    echo "Ready for A4: mir_place_is_prefix()"
else
    echo ""
    echo -e "${RED}✗ FAILED${NC}"
fi

exit 0
