#!/bin/bash

# Test script to validate array syntax conversions in neurx codebase

COMPILER=/Users/feifei/shuwen/s/bin/s
NEURX=/Users/feifei/shuwen/neurx
RESULTS_DIR=/tmp/neurx_compile_tests

mkdir -p "$RESULTS_DIR"

# Key files to test - these should have been converted
TEST_FILES=(
    "train_model.s"
    "train_demo.s"
    "training_simple.s"
    "training_system.s"
    "train_full_system.s"
    "train_llm.s"
    "train_llm_jsonl.s"
    "train_demo_modulo_native.s"
    "simple_train.s"
    "test_modulo.s"
    "checkpoint_restore.s"
    "checkpoint_operations.s"
)

echo "=== Neurx Array Syntax Validation ==="
echo "Compiler: $COMPILER"
echo ""

PASSED=0
FAILED=0

for file in "${TEST_FILES[@]}"; do
    filepath="$NEURX/$file"
    
    if [ ! -f "$filepath" ]; then
        echo "⚠ SKIP: $file (not found)"
        continue
    fi
    
    output_ir="$RESULTS_DIR/$(basename "$file" .s).ir"
    
    if $COMPILER "$filepath" "$output_ir" 2>&1 | grep -q "compiled"; then
        echo "✓ PASS: $file"
        ((PASSED++))
    else
        echo "✗ FAIL: $file"
        ((FAILED++))
        $COMPILER "$filepath" "$output_ir" 2>&1 | head -5
    fi
done

echo ""
echo "=== Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Results in: $RESULTS_DIR"
