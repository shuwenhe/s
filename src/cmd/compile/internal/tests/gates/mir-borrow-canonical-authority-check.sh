#!/bin/bash

# mir-borrow-canonical-authority-check.sh
# B1.4: Canonical Authority Audit
# Ensures Borrow shadow ownership semantics read structured mir_place facts only.

GATE_NAME="B1.4: Borrow Canonical Authority Audit"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

MIR_FILE="$PROJECT_ROOT/src/cmd/compile/internal/mir.s"
ANALYSIS_FILE="$PROJECT_ROOT/src/cmd/compile/internal/ownership/analysis.s"
B1_3_GATE="$PROJECT_ROOT/src/cmd/compile/internal/tests/gates/mir-loan-borrowed-place-query-check.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
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

check_func_contains() {
    local description="$1"
    local fname="$2"
    local pattern="$3"
    local file="$4"

    if awk -v fname="$fname" -v pattern="$pattern" '
        $0 ~ "^func " fname "\\(" { in_func = 1 }
        in_func && $0 ~ "^func " && $0 !~ "^func " fname "\\(" { in_func = 0 }
        in_func && $0 ~ pattern { found = 1 }
        END { exit found ? 0 : 1 }
    ' "$file"; then
        echo -e "${GREEN}✓${NC} $description"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} $description"
        ((FAIL++))
    fi
}

check_func_not_contains() {
    local description="$1"
    local fname="$2"
    local pattern="$3"
    local file="$4"

    if awk -v fname="$fname" -v pattern="$pattern" '
        $0 ~ "^func " fname "\\(" { in_func = 1 }
        in_func && $0 ~ "^func " && $0 !~ "^func " fname "\\(" { in_func = 0 }
        in_func && $0 ~ pattern { found = 1 }
        END { exit found ? 1 : 0 }
    ' "$file"; then
        echo -e "${GREEN}✓${NC} $description"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} $description"
        ((FAIL++))
    fi
}

echo "================================================================"
echo "$GATE_NAME"
echo "================================================================"
echo ""

echo "--- [1] Canonical Query Authority ---"
check_func_contains "mir_loan_borrowed_place reads canonical array" "mir_loan_borrowed_place" "facts.loan_borrowed_places" "$MIR_FILE"
check_func_not_contains "mir_loan_borrowed_place never reads legacy loan_places" "mir_loan_borrowed_place" "loan_places" "$MIR_FILE"
check_func_not_contains "mir_loan_borrowed_place never serializes place keys" "mir_loan_borrowed_place" "mir_place_key" "$MIR_FILE"

echo ""
echo "--- [2] Legacy Path Lifecycle ---"
check "loan_places marked legacy/debug only" "LEGACY / DEBUG" "$MIR_FILE"
check "loan_places has no semantic authority" "Authority: NONE" "$MIR_FILE"
check "loan_places removal TODO is explicit" "Remove after legacy diagnostic consumers migrate" "$MIR_FILE"
check "mir_place_key marked diagnostic/lookup helper" "diagnostic/lookup helper" "$MIR_FILE"

echo ""
echo "--- [3] Consumer Allowlist ---"
LEGACY_READERS="$(awk '
    /^func / {
        name = $2
        sub(/\(.*/, "", name)
        current = name
    }
    /facts\.loan_places/ {
        if (current != "build_ownership_facts_from_mir" &&
            current != "dump_ownership_analysis_input_from_mir" &&
            current != "mir_empty_ownership_facts") {
            print FILENAME ":" FNR ":" current ":" $0
        }
    }
' "$MIR_FILE")"

if [ -z "$LEGACY_READERS" ]; then
    echo -e "${GREEN}✓${NC} production legacy loan_places consumers are allowlisted"
    ((PASS++))
else
    echo -e "${RED}✗${NC} unallowlisted production loan_places consumer(s):"
    echo "$LEGACY_READERS"
    ((FAIL++))
fi

echo ""
echo "--- [4] Solver Boundary ---"
check_not "analysis input excludes legacy loan_places" "loan_places" "$ANALYSIS_FILE"
check_not "analysis input excludes canonical loan_borrowed_places" "loan_borrowed_places" "$ANALYSIS_FILE"
check_not "analysis input excludes mir_place_key" "mir_place_key" "$ANALYSIS_FILE"
check_not "analysis input excludes mir_loan_borrowed_place" "mir_loan_borrowed_place" "$ANALYSIS_FILE"

echo ""
echo "--- [5] Place Comparison Boundary ---"
check "Structural equality helper exists" "func mir_place_equal" "$MIR_FILE"
check "Structural prefix helper exists" "func mir_place_is_prefix" "$MIR_FILE"
check_func_not_contains "mir_place_equal avoids string key authority" "mir_place_equal" "mir_place_key|loan_places" "$MIR_FILE"
check_func_not_contains "mir_place_is_prefix avoids string key authority" "mir_place_is_prefix" "mir_place_key|loan_places" "$MIR_FILE"

echo ""
echo "--- [6] B1.3 Wording Does Not Claim Synthesis Authority ---"
check "B1.3 gate says independent queries exist" "Two independent queries now available" "$B1_3_GATE"
check "B1.3 gate says no synthesis/conflict authority yet" "No synthesis/conflict authority is established yet" "$B1_3_GATE"
check_not "B1.3 gate avoids together-evaluation authority language" "Both queries can be evaluated together" "$B1_3_GATE"

echo ""
echo "================================================================"
echo "Result: $PASS passed, $FAIL failed"
echo "================================================================"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ B1.4 COMPLETE${NC}"
    echo ""
    echo "Borrow canonical authority is sealed:"
    echo "  ✓ Semantic Loan→Place query reads loan_borrowed_places[L]"
    echo "  ✓ loan_places[] remains compatibility/diagnostics only"
    echo "  ✓ Solver remains Region/Loan liveness only"
    echo "  ✓ Structural place comparisons are the only semantic comparison path"
    echo ""
fi

exit $FAIL
