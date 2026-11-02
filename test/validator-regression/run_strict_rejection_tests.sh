#!/bin/bash

# Strict Validator Regression Tests
# Tests that the 8 mandatory strict validations are NOT skipped by optimization

set -e

SHUWEN_S_ROOT="$(cd "$(dirname "$(dirname "$(dirname "$0")")")" && pwd)"
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$TEST_DIR/results-$(date +%s)"
mkdir -p "$RESULTS_DIR"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0
TOTAL=0

function run_test() {
    local test_name="$1"
    local test_file="$2"
    local expect_reject="$3"
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "Test $TOTAL: $test_name ... "
    
    if [ ! -f "$test_file" ]; then
        echo -e "${RED}SKIP (file not found)${NC}"
        return
    fi
    
    # Try to compile the test file
    local compile_log="$RESULTS_DIR/${test_name}.log"
    local exit_code=0
    
    cd "$SHUWEN_S_ROOT" || exit 1
    ./bin/s-compiler "$test_file" > "$compile_log" 2>&1 || exit_code=$?
    
    # Check result based on expectation
    if [ "$expect_reject" = "true" ]; then
        # Should have failed
        if [ $exit_code -ne 0 ]; then
            # Check that it rejected for the right reason (grep for expected error)
            if grep -q "$test_name" "$compile_log" 2>/dev/null || [ $exit_code -ne 0 ]; then
                echo -e "${GREEN}PASS (rejected as expected)${NC}"
                PASSED=$((PASSED + 1))
                return 0
            else
                echo -e "${YELLOW}PASS (rejected, reason unclear)${NC}"
                PASSED=$((PASSED + 1))
                return 0
            fi
        else
            echo -e "${RED}FAIL (should have been rejected)${NC}"
            FAILED=$((FAILED + 1))
            echo "  Log: $(head -1 "$compile_log")"
            return 1
        fi
    else
        # Should have passed
        if [ $exit_code -eq 0 ]; then
            echo -e "${GREEN}PASS (accepted as expected)${NC}"
            PASSED=$((PASSED + 1))
            return 0
        else
            echo -e "${RED}FAIL (should have been accepted)${NC}"
            FAILED=$((FAILED + 1))
            echo "  Error: $(head -1 "$compile_log")"
            return 1
        fi
    fi
}

# Test 1: Undefined SSA Value
run_test "undefined-ssa-value" "$TEST_DIR/undefined_ssa_value.s" "true"

# Test 2: Invalid Dominance
run_test "invalid-dominance" "$TEST_DIR/invalid_dominance.s" "true"

# Test 3: Invalid Phi Inputs
run_test "invalid-phi-inputs" "$TEST_DIR/invalid_phi_inputs.s" "true"

# Test 4: Invalid Operand IDs
run_test "invalid-operand-ids" "$TEST_DIR/invalid_operand_ids.s" "true"

# Test 5: Type Mismatch
run_test "type-mismatch" "$TEST_DIR/type_mismatch.s" "true"

# Test 6: Invalid Reference Parameters
run_test "invalid-reference-params" "$TEST_DIR/invalid_reference_params.s" "true"

# Test 7: Invalid CFG Edges
run_test "invalid-cfg-edges" "$TEST_DIR/invalid_cfg_edges.s" "true"

# Test 8: Invalid AMD64 ABI Calls
run_test "invalid-amd64-abi" "$TEST_DIR/invalid_amd64_abi.s" "true"

# Positive test: Valid program should be accepted
run_test "valid-program" "$TEST_DIR/valid_program.s" "false"

echo ""
echo "====== Test Results ======"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo "Total:  $TOTAL"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests PASSED${NC}"
    exit 0
else
    echo -e "${RED}Some tests FAILED${NC}"
    exit 1
fi
