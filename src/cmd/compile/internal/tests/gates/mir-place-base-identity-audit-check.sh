#!/bin/bash

# mir-place-base-identity-audit-check.sh
# C.3.1b.2-pre.A2: Place Base Identity Audit
# Discovers what mir_place.root can actually represent
# NOT implementation, just documentation of current MIR semantics

GATE_NAME="C.3.1b.2-pre.A2: Place Base Identity Audit"
GATE_PHASE="discovery"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

MIR_FILE="$PROJECT_ROOT/src/cmd/compile/internal/mir.s"
LOWERING_DIR="$PROJECT_ROOT/src/cmd/compile/internal"

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
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $desc"
        ((PASS++))
        return 0
    else
        return 1
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

audit_finding() {
    local desc="$1"
    echo -e "${YELLOW}ℹ${NC} $desc"
}

echo "================================================================"
echo "$GATE_NAME"
echo "Status: $GATE_PHASE (discovery, NOT enforcing canonicity yet)"
echo "================================================================"
echo ""

echo "--- Current mir_place.root Representation ---"
check "mir_place.root exists as string" "$MIR_FILE" "string root"

echo ""
echo "--- Audit: What kinds of root identifiers exist? ---"

echo ""
echo "[1] Local Variables"
check_not "search: local variables detected in MIR lowering" "$MIR_FILE" "mir_place { root:"
if grep -q "mir_local_slot" "$MIR_FILE"; then
    echo -e "${YELLOW}ℹ${NC} MIR has mir_local_slot structure for local tracking"
    ((WARN++))
    audit_finding "Local IDs are available through mir_local_slot[] array"
fi

echo ""
echo "[2] Function Arguments"
if grep -q "params\|argument" "$MIR_FILE"; then
    echo -e "${YELLOW}ℹ${NC} MIR lowering processes function parameters"
    ((WARN++))
    audit_finding "Arguments may need separate identity from locals"
fi

echo ""
echo "[3] Return Place"
if grep -q "return\|return_place" "$MIR_FILE"; then
    echo -e "${YELLOW}ℹ${NC} Return value handling detected in MIR"
    ((WARN++))
    audit_finding "Return place may be separate identity category"
fi

echo ""
echo "[4] Static/Global Variables"
if grep -q "static\|global" "$MIR_FILE"; then
    echo -e "${YELLOW}ℹ${NC} References to static/global scope detected"
    ((WARN++))
else
    echo -e "${ORANGE}⚠${NC} No static/global support detected in current MIR"
    ((WARN++))
fi

echo ""
echo "[5] Temporary Values"
audit_finding "Temporaries created during expression evaluation"

echo ""
echo "--- Current Usage Pattern ---"
if grep -q "mir_place_from_expr" "$MIR_FILE"; then
    echo -e "${GREEN}✓${NC} mir_place_from_expr builds places from AST expressions"
    ((PASS++))
    audit_finding "All root identifiers flow through AST name/member/index"
fi

echo ""
echo "--- Type System Integration ---"
if grep -q "typesys\|type_name" "$MIR_FILE"; then
    echo -e "${YELLOW}ℹ${NC} MIR integrates with type system"
    ((WARN++))
    audit_finding "Type resolution happens at/after MIR construction"
    audit_finding "Field lookup (string → index) requires type info"
fi

echo ""
echo "--- Root String Format Analysis ---"
if grep -q "root: name_expr.name" "$MIR_FILE"; then
    echo -e "${YELLOW}ℹ${NC} Root comes from AST node names"
    ((WARN++))
    audit_finding "Current format: identifier string (e.g., '_1', 'x', 'obj')"
fi

echo ""
echo "================================================================"
TOTAL=$((PASS + FAIL + WARN))
echo "Result: $PASS discovered, $FAIL missing, $WARN audit notes"
echo "================================================================"

echo ""
echo "AUDIT FINDINGS:"
echo ""
echo "Current State:"
echo "  mir_place.root :: string (identifier)"
echo "  Only source: mir_place_from_expr() from AST"
echo ""
echo "Potential Root Categories:"
echo "  [✓] Local variable → string name (current)"
echo "  [?] Function argument → string name or separate index?"
echo "  [?] Return place → separate marker or string?"
echo "  [?] Static/global → not yet supported?"
echo "  [?] Temporary → numbered with what scheme?"
echo ""
echo "Design Choices for A2 → A3:"
echo ""
echo "Option 1: Keep root as string, improve typing"
echo "  + Minimal changes to existing code"
echo "  + Works for locals/args/temporaries"
echo "  - Requires name → local_id lookup at query time"
echo "  - Still semantic reconstruction (string → meaning)"
echo ""
echo "Option 2: Introduce mir_place_base enum"
echo "  enum mir_place_base {"
echo "      Local(id)"
echo "      Argument(id)"  
echo "      Return"
echo "      Temporary(id)"
echo "      Static(id)"
echo "      Global(id)"
echo "  }"
echo "  + Type-safe categorization"
echo "  + No semantic reconstruction needed"
echo "  - Requires MIR lowering refactoring"
echo "  - Bigger canonical canonicalization"
echo ""
echo "RECOMMENDATION FOR NEXT STEP (A2 → A3):"
echo "After this discovery, user should decide:"
echo "  - Continue with string root + improve equality (smaller change)"
echo "  - Or introduce mir_place_base (larger but cleaner long-term)"
echo ""
echo "For now, A3 can proceed with string root and add structural equality."
echo "mir_place_base can be introduced in A2.1 if beneficial."
echo ""

exit 0
