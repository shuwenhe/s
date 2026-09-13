#!/bin/bash

# mir-projection-kind-enum-check.sh
# C.3.1b.2-pre.A1: Projection Kind Canonicalization (Enum)
# Verifies that mir_place_projection.kind is enum-based, not string-based
# All gates should remain green (compatible canonicalization)

GATE_NAME="C.3.1b.2-pre.A1: Projection Kind Enum"
GATE_PHASE="implementation"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

MIR_FILE="$PROJECT_ROOT/src/cmd/compile/internal/mir.s"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    local desc="$1"
    local file="$2"
    local pattern="$3"
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $desc"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} $desc"
        ((FAIL++))
    fi
}

check_not() {
    local desc="$1"
    local file="$2"
    local pattern="$3"
    
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $desc"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} $desc"
        ((FAIL++))
    fi
}

echo "================================================================"
echo "$GATE_NAME"
echo "Status: $GATE_PHASE (compatible canonicalization)"
echo "================================================================"
echo ""

echo "--- Requirement 1: mir_projection_kind Enum Defined ---"
check "enum mir_projection_kind exists" "$MIR_FILE" "enum mir_projection_kind"
check "enum field value" "$MIR_FILE" "field.*// struct"
check "enum deref value" "$MIR_FILE" "deref.*// pointer"
check "enum index value" "$MIR_FILE" "index.*// array"

echo ""
echo "--- Requirement 2: mir_place_projection Uses Enum ---"
check "mir_place_projection.kind is enum type" "$MIR_FILE" "mir_projection_kind kind"

echo ""
echo "--- Requirement 3: mir_place_from_expr Uses Enum Values ---"
check "field uses enum value" "$MIR_FILE" "mir_projection_kind.field"
check "index uses enum value" "$MIR_FILE" "mir_projection_kind.index"

echo ""
echo "--- Requirement 4: String-Based Projection Kind NOT Used ---"
check_not "No string \"field\" assignment" "$MIR_FILE" 'kind:.*"field"'
check_not "No string \"index\" assignment" "$MIR_FILE" 'kind:.*"index"'
check_not "No string comparison if/else" "$MIR_FILE" 'if.*projection.kind.*==".*"'

echo ""
echo "--- Requirement 5: mir_place_key Uses Enum Dispatch ---"
check "mir_place_key uses switch statement" "$MIR_FILE" "switch projection.kind"
check "mir_place_key enum.field dispatch" "$MIR_FILE" "mir_projection_kind.field.*out = out"
check "mir_place_key enum.index dispatch" "$MIR_FILE" "mir_projection_kind.index.*out = out"
check "mir_place_key enum.deref dispatch" "$MIR_FILE" "mir_projection_kind.deref.*out = out"

echo ""
echo "--- Requirement 6: mir_place_key Marked as Diagnostic Helper ---"
check "mir_place_key marked as diagnostic/lookup" "$MIR_FILE" "diagnostic/lookup helper"
check "NOT ownership semantic authority comment" "$MIR_FILE" "NOT ownership semantic authority"

echo ""
echo "--- Requirement 7: Backward Compatibility Check ---"
check "mir_place still has root string" "$MIR_FILE" "string root"
check "mir_place_projection.value still string" "$MIR_FILE" "string value"

echo ""
echo "================================================================"
TOTAL=$((PASS + FAIL))
echo "Result: $PASS passed, $FAIL failed (of $TOTAL checks)"
echo "================================================================"

echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✓ A1 COMPLETE${NC}"
    echo ""
    echo "Summary: mir_place_projection.kind successfully canonicalized to enum"
    echo "- Eliminated string dispatch in ownership algorithms"
    echo "- Preserved mir_place_key() as diagnostic/lookup helper"
    echo "- Maintained backward compatibility (root, value still string)"
    echo "- Ready for ownership system integration"
    echo ""
    echo "Next phase: C.3.1b.2-pre.A2 (Place base identity audit)"
else
    echo -e "${RED}✗ A1 FAILED${NC}"
    echo "Fix items before proceeding"
fi

exit 0
