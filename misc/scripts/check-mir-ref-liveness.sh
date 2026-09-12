#!/bin/bash

# check-mir-ref-liveness.sh
# Test driver for Reference Liveness analysis
#
# Usage:
#   bash misc/scripts/check-mir-ref-liveness.sh [test_name]
#   bash misc/scripts/check-mir-ref-liveness.sh              # run all tests
#
# This script:
#   1. Compiles each test case to MIR
#   2. Runs reference liveness analysis
#   3. Checks place borrow conflicts
#   4. Compares with expected results

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_DIR="$REPO_ROOT/test/mir_ref_liveness"
MIR_OUT="$TEST_DIR/.mir_output"
RESULTS="$TEST_DIR/.results"

# Create temp directories
mkdir -p "$MIR_OUT" "$RESULTS"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test definitions as arrays (bash compatible)
TESTS=(
    "straight_last_use"
    "same_place_still_live"
    "branch_all_paths_dead"
    "branch_live_after_join"
    "loop_backedge"
    "disjoint_place"
)

EXPECTED=(
    "ALLOW"
    "CONFLICT"
    "CONFLICT"
    "CONFLICT"
    "CONFLICT"
    "ALLOW"
)

# Function to compile S source to MIR
compile_to_mir() {
    local test_name="$1"
    local src="$TEST_DIR/test_cases.s"
    local mir_out="$MIR_OUT/${test_name}.mir"
    
    # Placeholder: would be actual S compiler invocation
    # For now, just touch file to indicate compilation
    # s --emit-mir --filter-func "$test_name" "$src" > "$mir_out" 2>&1 || true
    
    touch "$mir_out"
    echo "$mir_out"
}

# Function to run reference liveness analysis
analyze_ref_liveness() {
    local mir_file="$1"
    local test_name="$2"
    local result_file="$RESULTS/${test_name}.liveness"
    
    # Placeholder: would invoke s --emit-mir-ref-liveness
    # s --emit-mir-ref-liveness "$mir_file" > "$result_file" 2>&1 || true
    
    # For now, create stub result
    cat > "$result_file" <<EOF
[reference_liveness: $test_name]
# Backward liveness analysis results
# live_in/live_out to be populated by actual analyzer
EOF
    
    echo "$result_file"
}

# Function to check place borrow conflicts
check_conflicts() {
    local liveness_file="$1"
    local test_name="$2"
    local conflict_file="$RESULTS/${test_name}.conflicts"
    
    # Placeholder: would invoke conflict checker
    # s --check-place-borrow-conflicts "$liveness_file" > "$conflict_file" 2>&1 || true
    
    # For now, return placeholder
    # In RED phase: return random/stub results
    # Once analyzer implemented: return actual analysis
    
    echo "PLACEHOLDER" > "$conflict_file"
    echo "$conflict_file"
}

# Main test runner
run_test() {
    local test_num="$1"
    local test_name="${TESTS[$test_num]}"
    local expected="${EXPECTED[$test_num]}"
    
    if [[ -z "$test_name" ]]; then
        return
    fi
    
    echo -n "Testing: $test_name ... "
    
    # Step 1: Compile to MIR
    local mir_file
    mir_file=$(compile_to_mir "$test_name") || {
        echo -e "${RED}FAIL${NC} (compilation)"
        return 1
    }
    
    # Step 2: Run reference liveness analysis  
    local liveness_file
    liveness_file=$(analyze_ref_liveness "$mir_file" "$test_name") || {
        echo -e "${RED}FAIL${NC} (liveness analysis)"
        return 1
    }
    
    # Step 3: Check conflicts
    local conflict_file
    conflict_file=$(check_conflicts "$liveness_file" "$test_name") || {
        echo -e "${RED}FAIL${NC} (conflict check)"
        return 1
    }
    
    # Step 4: Extract result and compare
    local actual
    actual=$(grep -E "(ALLOW|CONFLICT|PLACEHOLDER)" "$conflict_file" | head -1 | awk '{print $1}') || {
        actual="ERROR"
    }
    
    if [[ "$actual" == "$expected" ]]; then
        echo -e "${GREEN}PASS${NC}"
        return 0
    else
        echo -e "${RED}FAIL${NC} (expected=$expected, got=$actual)"
        return 1
    fi
}

# Parse arguments
FILTER="${1:-}"
PASS=0
FAIL=0

echo "=========================================="
echo "Reference Liveness Test Suite"
echo "=========================================="
echo ""

# Run tests
for ((i=0; i<${#TESTS[@]}; i++)); do
    test_name="${TESTS[$i]}"
    
    if [[ -z "$FILTER" ]] || [[ "$test_name" == "$FILTER" ]]; then
        if run_test "$i"; then
            ((PASS++))
        else
            ((FAIL++))
        fi
    fi
done

echo ""
echo "=========================================="
echo "Results: ${GREEN}$PASS PASS${NC} ${RED}$FAIL FAIL${NC}"
echo "=========================================="

# Cleanup
# rm -rf "$MIR_OUT" "$RESULTS"  # Uncomment after debugging

exit $([[ $FAIL -eq 0 ]] && echo 0 || echo 1)
