#!/bin/bash
# Verify that all 8 strict validation checks are present and active

set -e

SHUWEN_S_ROOT="$(cd "$(dirname "$(dirname "$(dirname "$0")")")" && pwd)"
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CHECKS_PASSED=0
CHECKS_TOTAL=8

echo "Verifying Strict Validation Checks..."
echo ""

# Check 1: Undefined SSA Value
echo -n "1. Undefined SSA Value Detection ... "
if grep -q "unknown operand\|unknown terminator value" "$SHUWEN_S_ROOT/src/cmd/compile/internal/ssa/program.s"; then
    echo -e "${GREEN}FOUND${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}MISSING${NC}"
fi

# Check 2: Invalid Dominance
echo -n "2. Invalid Dominance Detection ... "
if grep -q "nondominating operand" "$SHUWEN_S_ROOT/src/cmd/compile/internal/ssa/program.s"; then
    echo -e "${GREEN}FOUND${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}MISSING${NC}"
fi

# Check 3: Invalid Phi Inputs
echo -n "3. Invalid Phi Inputs Detection ... "
if grep -q "phi operand count\|phi operand type" "$SHUWEN_S_ROOT/src/cmd/compile/internal/ssa/program.s"; then
    echo -e "${GREEN}FOUND${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}MISSING${NC}"
fi

# Check 4: Invalid Operand IDs
echo -n "4. Invalid Operand IDs Detection ... "
if grep -q "invalid copy\|copy type" "$SHUWEN_S_ROOT/src/cmd/compile/internal/ssa/program.s"; then
    echo -e "${GREEN}FOUND${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}MISSING${NC}"
fi

# Check 5: Type Mismatch
echo -n "5. Type Mismatch Detection ... "
if grep -q "parameter type\|return type\|value type\|SSA comparison operand type mismatch" "$SHUWEN_S_ROOT/src/cmd/compile/internal/ssa/program.s"; then
    echo -e "${GREEN}FOUND${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}MISSING${NC}"
fi

# Check 6: Invalid Reference Parameters
echo -n "6. Invalid Reference Parameters Detection ... "
if grep -q "SSA aliased mutable call reference\|SSA reference\|SSA unproven reference" "$SHUWEN_S_ROOT/src/cmd/compile/internal/ssa/program.s"; then
    echo -e "${GREEN}FOUND${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}MISSING${NC}"
fi

# Check 7: Invalid CFG Edges
echo -n "7. Invalid CFG Edges Detection ... "
if grep -q "unknown predecessor\|unknown successor\|inconsistent predecessor edge\|inconsistent successor edge" "$SHUWEN_S_ROOT/src/cmd/compile/internal/ssa/program.s"; then
    echo -e "${GREEN}FOUND${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}MISSING${NC}"
fi

# Check 8: Invalid AMD64 ABI Calls
echo -n "8. Invalid AMD64 ABI Calls Detection ... "
if grep -q "amd64: unsupported" "$SHUWEN_S_ROOT/src/cmd/compile/internal/codegen/amd64_program.s"; then
    echo -e "${GREEN}FOUND${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo -e "${RED}MISSING${NC}"
fi

echo ""
echo "====== Validation Checks Summary ======"
echo "Found: $CHECKS_PASSED/$CHECKS_TOTAL"

if [ $CHECKS_PASSED -eq $CHECKS_TOTAL ]; then
    echo -e "${GREEN}All 8 mandatory strict validation checks are present${NC}"
    exit 0
else
    echo -e "${RED}Some mandatory checks are missing!${NC}"
    exit 1
fi
