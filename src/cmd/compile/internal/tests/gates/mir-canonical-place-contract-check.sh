#!/bin/bash

# mir-canonical-place-contract-check.sh
# C.3.1b.2-pre.1: Canonical mir_place Contract Audit
# Records whether mir_place meets canonical representation requirements
# Does NOT enforce changes - only documents current state

GATE_NAME="C.3.1b.2-pre.1: Canonical mir_place Contract"
GATE_PHASE="discovery"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

MIR_FILE="$PROJECT_ROOT/src/cmd/compile/internal/mir.s"
OWNERSHIP_DIR="$PROJECT_ROOT/src/cmd/compile/internal/ownership"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check() {
    local desc="$1"
    local file="$2"
    local pattern="$3"
    local expected="pass"
    
    if [ "$4" != "" ]; then
        expected="$4"
    fi
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        result="found"
    else
        result="not_found"
    fi
    
    if [ "$expected" = "pass" ] && [ "$result" = "found" ]; then
        echo -e "${GREEN}✓${NC} $desc"
        ((PASS++))
    elif [ "$expected" = "fail" ] && [ "$result" = "not_found" ]; then
        echo -e "${RED}✗${NC} $desc"
        ((FAIL++))
    elif [ "$expected" = "warn" ]; then
        echo -e "${ORANGE}⚠${NC} $desc (STRING BASED)"
        ((WARN++))
    else
        echo -e "${RED}✗${NC} $desc"
        ((FAIL++))
    fi
}

echo "================================================================"
echo "$GATE_NAME"
echo "Status: $GATE_PHASE (discovery, NOT enforcing)"
echo "================================================================"
echo ""

echo "--- Requirement 1: Root Identity Representation ---"
check "mir_place.root exists" "$MIR_FILE" "string root" "pass"
if grep -q "struct mir_place {" "$MIR_FILE" && grep -A3 "struct mir_place {" "$MIR_FILE" | grep -q "string root"; then
    echo -e "${RED}✗${NC} mir_place.root is string (should be int local_id)"
    ((FAIL++))
fi

echo ""
echo "--- Requirement 2: Projection Kind Representation ---"
check "mir_place_projection.kind exists" "$MIR_FILE" "struct mir_place_projection" "pass"
if grep -A2 "struct mir_place_projection" "$MIR_FILE" | grep -q "string kind"; then
    echo -e "${YELLOW}⚠${NC} projection.kind is string (should be enum)"
    ((WARN++))
fi

echo ""
echo "--- Requirement 3: Projection Value Representation ---"
check "mir_place_projection.value exists" "$MIR_FILE" "string value" "pass"
echo -e "${YELLOW}⚠${NC} projection.value is string (should be int for field, expr for index)"
((WARN++))

echo ""
echo "--- Requirement 4: Deref Support ---"
if grep -q "kind.*deref\|deref.*kind" "$MIR_FILE"; then
    echo -e "${GREEN}✓${NC} Deref projection supported"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Deref projection NOT supported (MISSING)"
    ((FAIL++))
fi

echo ""
echo "--- Requirement 5: Nested Projection Representation ---"
if grep -q "mir_place_projection\[\]" "$MIR_FILE"; then
    echo -e "${GREEN}✓${NC} Projections are array (composable)"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Projections not array"
    ((FAIL++))
fi

echo ""
echo "--- Requirement 6: No String Serialization in Core ---"
if grep -q "mir_place_key" "$MIR_FILE"; then
    echo -e "${RED}✗${NC} mir_place_key() serializes to string (defeats canonicity)"
    ((FAIL++))
    echo "     Uses textual reconstruction: root + projection + projection + ..."
fi

echo ""
echo "--- Requirement 7: Canonical Equality Function ---"
if grep -q "func.*place.*equal\|func.*compare.*place" "$MIR_FILE"; then
    echo -e "${GREEN}✓${NC} Canonical equality function exists"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Canonical equality function MISSING"
    ((FAIL++))
fi

echo ""
echo "--- Requirement 8: Canonical Prefix/Ancestor Function ---"
if grep -q "func.*place.*prefix\|func.*place.*ancestor" "$MIR_FILE"; then
    echo -e "${GREEN}✓${NC} Prefix checking function exists"
    ((PASS++))
else
    echo -e "${RED}✗${NC} Prefix checking function MISSING"
    ((FAIL++))
fi

echo ""
echo "--- Requirement 9: mir_place Construction from AST ---"
check "mir_place_from_expr exists" "$MIR_FILE" "mir_place_from_expr" "pass"

echo ""
echo "--- Requirement 10: Ownership System Integration ---"
if find "$OWNERSHIP_DIR" -name "*.s" -exec grep -l "mir_place" {} \; 2>/dev/null | grep -q .; then
    echo -e "${GREEN}✓${NC} ownership/ references mir_place"
    ((PASS++))
else
    echo -e "${RED}✗${NC} ownership/ does NOT use mir_place (ZERO INTEGRATION)"
    ((FAIL++))
    echo "     Current: ownership/ uses string place exclusively"
fi

echo ""
echo "================================================================"
TOTAL=$((PASS + FAIL + WARN))
echo "Result: $PASS passed, $FAIL failed, $WARN warnings (of $TOTAL checks)"
echo "================================================================"

echo ""
if [ $FAIL -gt 0 ]; then
    echo "CANONICITY ASSESSMENT: 🔴 NOT CANONICAL"
    echo ""
    echo "Reasons:"
    if grep -q "string root" "$MIR_FILE"; then
        echo "  1. Root is string → requires name resolution"
    fi
    if grep -q "struct mir_place_projection" "$MIR_FILE" && grep -A2 "struct mir_place_projection" "$MIR_FILE" | grep -q "string kind"; then
        echo "  2. Kind is string → semantic reconstruction at each use"
    fi
    if grep -q "struct mir_place_projection" "$MIR_FILE" && grep -A2 "struct mir_place_projection" "$MIR_FILE" | grep -q "string value"; then
        echo "  3. Value is string → field lookup required (not indexed)"
    fi
    if ! grep -q "kind.*deref" "$MIR_FILE"; then
        echo "  4. Deref not supported → incomplete for references"
    fi
    if grep -q "mir_place_key" "$MIR_FILE"; then
        echo "  5. String serialization → defeats structural canonicity"
    fi
    if ! grep -q "func.*place.*equal" "$MIR_FILE"; then
        echo "  6. No canonical equality → comparison relies on string key"
    fi
    if ! find "$OWNERSHIP_DIR" -name "*.s" -exec grep -l "mir_place" {} \; 2>/dev/null | grep -q .; then
        echo "  7. Zero integration → ownership/ ignores mir_place"
    fi
fi

echo ""
echo "OPTIONS FOR C.3.1b.2-pre.1 COMPLETION:"
echo ""
echo "  Path A: Refactor mir_place to canonical"
echo "    ├─ Change root: string → int (local_id)"
echo "    ├─ Change kind: string → enum"
echo "    ├─ Change field value: string → int"
echo "    ├─ Add deref support"
echo "    ├─ Remove mir_place_key() string serialization"
echo "    ├─ Add canonical_equal(), canonical_prefix()"
echo "    └─ Wire into ownership/"
echo "    Cost: Heavy refactoring (~2-3 weeks)"
echo ""
echo "  Path B: Define canonical_place separately"
echo "    ├─ Create new canonical_place type"
echo "    ├─ Keep mir_place as diagnostic layer"
echo "    ├─ Add converters: mir_place ↔ canonical_place"
echo "    └─ Use canonical_place in ownership/"
echo "    Cost: Faster (~1-2 weeks) but adds type duplication"
echo ""
echo "DECISION REQUIRED: User must choose Path A or Path B"
echo ""

exit 0
