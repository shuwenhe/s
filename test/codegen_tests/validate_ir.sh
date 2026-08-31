#!/bin/bash

# Quick IR Validation - Check generated IR format without execution

S_SEED="/home/shuwen/shuwen/s/bin/s_seed"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}S Compiler - IR Format Validation${NC}"
echo -e "${BLUE}================================================${NC}\n"

PASSED=0
FAILED=0

test_ir_output() {
    local name=$1
    local source=$2
    local expected_pattern=$3
    
    echo -n "Testing $name IR output... "
    
    IR_FILE="/tmp/test_$name.ir"
    
    if $S_SEED ir "$source" -o "$IR_FILE" 2>/dev/null; then
        if grep -q "$expected_pattern" "$IR_FILE"; then
            echo -e "${GREEN}✅ PASS${NC}"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}❌ FAIL${NC} (IR doesn't contain: $expected_pattern)"
            echo "Generated IR:"
            head -5 "$IR_FILE"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "${RED}❌ FAIL${NC} (compilation error)"
        FAILED=$((FAILED + 1))
    fi
    
    rm -f "$IR_FILE"
}

echo "=== Test Programs ==="
echo ""

# Test 1: Arithmetic
test_ir_output "arithmetic" \
    "/home/shuwen/shuwen/s/test/codegen_tests/test_programs/arithmetic.s" \
    "ADD"

# Test 2: Function call
test_ir_output "function_call" \
    "/home/shuwen/shuwen/s/test/codegen_tests/test_programs/function_call.s" \
    "CALL"

# Test 3: Loop
test_ir_output "loop" \
    "/home/shuwen/shuwen/s/test/codegen_tests/test_programs/loop.s" \
    "LABEL\|JUMP"

echo ""
echo "================================================"
echo -e "Results: ${GREEN}Passed: $PASSED${NC}, ${RED}Failed: $FAILED${NC}"
echo "================================================"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL IR VALIDATION PASSED${NC}"
    exit 0
else
    echo -e "${RED}❌ SOME VALIDATION FAILED${NC}"
    exit 1
fi
