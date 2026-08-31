#!/bin/bash

# Native Code Generation Test Runner
# Complete validation suite for S compiler direct code generation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Paths
CODEGEN_DIR="/home/shuwen/shuwen/s/src/cmd/compile/seed/codegen"
TESTPROG_DIR="/home/shuwen/shuwen/s/test/codegen_tests/test_programs"
RESULTS_LOG="./test_results.log"

# Tool paths
S_SEED="/home/shuwen/shuwen/s/bin/s_seed"
S_IR_RUNNER="/home/shuwen/shuwen/neurx/build/s_ir_runner"

# Add to PATH if not already there
export PATH="/home/shuwen/shuwen/s/bin:$PATH"

# Utility functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

print_info() {
    echo -e "${BLUE}ℹ️ INFO${NC}: $1"
}

# Phase 1: Check environment
check_environment() {
    print_header "PHASE 1: Environment Check"
    
    print_info "Checking S compiler..."
    if [ -x "$S_SEED" ]; then
        print_pass "$S_SEED compiler found at $S_SEED"
    else
        print_fail "$S_SEED compiler not found at $S_SEED"
        return 1
    fi
    
    print_info "Checking IR runner..."
    if [ -x "$S_IR_RUNNER" ]; then
        print_pass "$S_IR_RUNNER found at $S_IR_RUNNER"
    else
        print_fail "$S_IR_RUNNER not found at $S_IR_RUNNER"
        return 1
    fi
    
    print_info "Checking directories..."
    if [ -d "$CODEGEN_DIR" ]; then
        print_pass "Codegen directory exists"
    else
        print_fail "Codegen directory not found: $CODEGEN_DIR"
        return 1
    fi
    
    if [ -d "$TESTPROG_DIR" ]; then
        print_pass "Test programs directory exists"
    else
        print_fail "Test programs directory not found: $TESTPROG_DIR"
        return 1
    fi
    
    print_info "Checking test files..."
    local test_files=("arithmetic.s" "function_call.s" "nested_calls.s" "loop.s" "recursive.s")
    for file in "${test_files[@]}"; do
        if [ -f "$TESTPROG_DIR/$file" ]; then
            print_pass "Found $file"
        else
            print_fail "Missing test program: $file"
            return 1
        fi
    done
}

# Phase 2: Unit Tests
run_unit_tests() {
    print_header "PHASE 2: Unit Tests"
    
    print_info "Compiling test_native.s..."
    cd "$CODEGEN_DIR"
    
    if $S_SEED test_native.s -o test_native.ir 2>/dev/null; then
        print_pass "Compilation successful"
    else
        print_fail "Compilation of test_native.s failed"
        return 1
    fi
    
    print_info "Running unit tests..."
    if output=$($S_IR_RUNNER test_native.ir 2>&1); then
        if echo "$output" | grep -q "PASS"; then
            print_pass "Unit tests passed"
            echo "$output" | grep "Passed:"
        else
            print_fail "Unit tests failed"
            echo "$output"
            return 1
        fi
    else
        print_fail "Unit test execution failed"
        return 1
    fi
    
    # Cleanup
    rm -f test_native.ir
}

# Phase 3: IR Method (Baseline)
run_ir_tests() {
    print_header "PHASE 3: IR Method Tests (Baseline)"
    
    cd "$TESTPROG_DIR"
    
    local programs=("arithmetic" "function_call" "nested_calls" "loop")
    local expected_results=("3" "8" "60" "45")
    
    for i in "${!programs[@]}"; do
        prog="${programs[$i]}"
        expected="${expected_results[$i]}"
        
        print_info "Testing $prog.s with IR method..."
        
        if $S_SEED "$prog.s" -o "$prog.ir" 2>/dev/null; then
            if output=$($S_IR_RUNNER "$prog.ir" 2>&1); then
                # Extract return code or output
                result=$(echo "$output" | tail -1 | tr -d '\n')
                if [ "$result" == "$expected" ]; then
                    print_pass "$prog returned $result (expected: $expected)"
                else
                    print_fail "$prog returned $result (expected: $expected)"
                fi
            else
                print_fail "$prog execution failed with IR method"
            fi
            rm -f "$prog.ir"
        else
            print_fail "$prog compilation failed with IR method"
        fi
    done
}

# Phase 4: Native Method (New)
run_native_tests() {
    print_header "PHASE 4: Native Method Tests (New)"
    
    cd "$TESTPROG_DIR"
    
    local programs=("arithmetic" "function_call" "nested_calls" "loop")
    local expected_results=("3" "8" "60" "45")
    
    for i in "${!programs[@]}"; do
        prog="${programs[$i]}"
        expected="${expected_results[$i]}"
        
        print_info "Testing $prog.s with native method..."
        
        if $S_SEED "$prog.s" -o "$prog" --native 2>/dev/null; then
            if [ -x "$prog" ]; then
                if output=$("./$prog" 2>&1); then
                    result=$(echo "$output" | tail -1 | tr -d '\n')
                    if [ "$result" == "$expected" ]; then
                        print_pass "$prog returned $result (expected: $expected)"
                    else
                        print_fail "$prog returned $result (expected: $expected)"
                    fi
                else
                    print_fail "$prog execution failed with native method"
                fi
                rm -f "$prog"
            else
                print_fail "$prog not executable after compilation"
            fi
        else
            print_fail "$prog compilation failed with native method"
            # Try to show error
            $S_SEED "$prog.s" -o "$prog" --native 2>&1 | head -5
        fi
    done
}

# Phase 5: Correctness Validation
validate_correctness() {
    print_header "PHASE 5: Correctness Validation"
    
    cd "$TESTPROG_DIR"
    
    print_info "Comparing IR and native results..."
    
    local programs=("arithmetic" "function_call" "nested_calls" "loop")
    
    for prog in "${programs[@]}"; do
        # Compile with IR
        if $S_SEED "$prog.s" -o "$prog.ir" 2>/dev/null && \
           ir_result=$($S_IR_RUNNER "$prog.ir" 2>&1); then
            
            # Compile with native
            if $S_SEED "$prog.s" -o "$prog" --native 2>/dev/null && \
               [ -x "$prog" ] && \
               native_result=$("./$prog" 2>&1); then
                
                # Compare results
                if [ "$ir_result" == "$native_result" ]; then
                    print_pass "$prog: Both methods agree (result: $ir_result)"
                else
                    print_fail "$prog: IR=$ir_result vs Native=$native_result"
                fi
            else
                print_fail "$prog: Native compilation/execution failed"
            fi
            
            rm -f "$prog.ir" "$prog"
        else
            print_fail "$prog: IR compilation/execution failed"
        fi
    done
}

# Phase 6: Performance Benchmark
run_performance_tests() {
    print_header "PHASE 6: Performance Benchmark"
    
    cd "$TESTPROG_DIR"
    
    print_info "Creating benchmark program..."
    cat > benchmark_loop.s << 'EOF'
package main

func benchmark() int {
    int sum = 0
    int i = 0
    for i < 1000000 {
        sum = sum + i
        i = i + 1
    }
    sum
}

func main() int {
    benchmark()
}
EOF
    
    # IR benchmark
    print_info "Benchmarking IR method (1M iterations)..."
    if $S_SEED benchmark_loop.s -o benchmark_loop.ir 2>/dev/null; then
        ir_start=$(date +%s%N)
        $S_IR_RUNNER benchmark_loop.ir > /dev/null 2>&1
        ir_end=$(date +%s%N)
        ir_time=$(( (ir_end - ir_start) / 1000000 ))  # Convert to ms
        print_pass "IR benchmark: ${ir_time}ms"
    else
        print_fail "IR benchmark compilation failed"
        ir_time=0
    fi
    
    # Native benchmark
    print_info "Benchmarking native method (1M iterations)..."
    if $S_SEED benchmark_loop.s -o benchmark_loop --native 2>/dev/null && [ -x benchmark_loop ]; then
        native_start=$(date +%s%N)
        ./benchmark_loop > /dev/null 2>&1
        native_end=$(date +%s%N)
        native_time=$(( (native_end - native_start) / 1000000 ))  # Convert to ms
        print_pass "Native benchmark: ${native_time}ms"
        
        # Calculate speedup
        if [ "$native_time" -gt 0 ]; then
            speedup=$(echo "scale=1; $ir_time / $native_time" | bc 2>/dev/null || echo "N/A")
            print_info "Speedup: ${speedup}x"
            
            # Check if target achieved
            if (( $(echo "$speedup >= 10" | bc -l 2>/dev/null || echo 0) )); then
                print_pass "Performance target achieved (≥10x)"
            else
                print_fail "Performance below target (target: ≥10x, got: ${speedup}x)"
            fi
        fi
    else
        print_fail "Native benchmark compilation failed"
    fi
    
    # Cleanup
    rm -f benchmark_loop.s benchmark_loop.ir benchmark_loop
}

# Summary
print_summary() {
    print_header "TEST SUMMARY"
    
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    
    echo "Passed:  $TESTS_PASSED"
    echo "Failed:  $TESTS_FAILED"
    echo "Skipped: $TESTS_SKIPPED"
    echo "Total:   $total"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}✅ ALL TESTS PASSED!${NC}\n"
        return 0
    else
        echo -e "\n${RED}❌ SOME TESTS FAILED!${NC}\n"
        return 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "S Compiler - Native Code Generation Test Suite"
    echo "================================================"
    echo -e "${NC}"
    
    # Create log
    > "$RESULTS_LOG"
    
    # Run phases
    check_environment || exit 1
    run_unit_tests || echo "⚠️  Unit tests skipped"
    run_ir_tests || echo "⚠️  IR tests had issues"
    run_native_tests || echo "⚠️  Native tests had issues"
    validate_correctness || echo "⚠️  Correctness validation had issues"
    run_performance_tests || echo "⚠️  Performance tests had issues"
    
    # Print summary
    print_summary
    
    return $?
}

# Run
main "$@"
