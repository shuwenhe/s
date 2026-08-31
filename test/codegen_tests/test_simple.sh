#!/bin/bash

# Simple Module Validation Test - No Package Dependencies
# Tests core logic without relying on module imports

set -e

S_SEED="/home/shuwen/shuwen/s/bin/s_seed"
S_IR_RUNNER="/home/shuwen/shuwen/neurx/build/s_ir_runner"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}S Compiler - Module Logic Validation${NC}"
echo -e "${BLUE}================================================${NC}\n"

PASSED=0
FAILED=0

test_program() {
    local name=$1
    local file=$2
    local expected=$3
    
    echo -n "Testing $name... "
    
    if $S_SEED ir "$file" -o /tmp/test_$name.ir 2>/dev/null; then
        result=$($S_IR_RUNNER /tmp/test_$name.ir 2>&1)
        if [ "$result" == "$expected" ]; then
            echo -e "${GREEN}✅ PASS${NC} (result: $result)"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}❌ FAIL${NC} (expected: $expected, got: $result)"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "${RED}❌ FAIL${NC} (compilation error)"
        FAILED=$((FAILED + 1))
    fi
    
    rm -f /tmp/test_$name.ir
}

echo "=== Core Module Logic Tests ==="
echo ""

# Test 1: Basic arithmetic
test_program "arithmetic" \
    "/home/shuwen/shuwen/s/test/codegen_tests/test_programs/arithmetic.s" \
    "3"

# Test 2: Function call
test_program "function_call" \
    "/home/shuwen/shuwen/s/test/codegen_tests/test_programs/function_call.s" \
    "8"

# Test 3: Nested calls
test_program "nested_calls" \
    "/home/shuwen/shuwen/s/test/codegen_tests/test_programs/nested_calls.s" \
    "60"

# Test 4: Loop
test_program "loop" \
    "/home/shuwen/shuwen/s/test/codegen_tests/test_programs/loop.s" \
    "45"

# Test 5: Simple module logic
test_program "module_logic" \
    "/home/shuwen/shuwen/s/test/codegen_tests/test_modules_simple.s" \
    "0"

echo ""
echo "================================================"
echo -e "Results: ${GREEN}Passed: $PASSED${NC}, ${RED}Failed: $FAILED${NC}"
echo "================================================"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    exit 1
fi
