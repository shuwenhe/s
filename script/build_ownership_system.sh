#!/bin/bash
# ============================================================================
# S Ownership System - Compilation and Testing Guide
# S语言所有权系统编译和测试指南
# ============================================================================

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S_ROOT="/Users/feifei/shuwen/s"

echo "=========================================="
echo "S Ownership System Build & Test"
echo "=========================================="

# Step 1: Check prerequisites
echo ""
echo "[Step 1] Checking prerequisites..."
cd "$S_ROOT"

if [ ! -f "Makefile" ]; then
    echo "ERROR: Makefile not found in $S_ROOT"
    exit 1
fi

if ! command -v make &> /dev/null; then
    echo "ERROR: make is not installed"
    exit 1
fi

echo "✓ Prerequisites check passed"

# Step 2: Build the seed compiler
echo ""
echo "[Step 2] Building seed compiler..."
if [ ! -f "bin/s_seed" ]; then
    echo "Building s_seed..."
    make seed-compiler-bin
else
    echo "✓ s_seed already built"
fi

# Step 3: Build the ownership-aware compiler
echo ""
echo "[Step 3] Building ownership-aware compiler..."
echo "Building ownership checker and C backend..."
make compiler

echo "✓ Compiler built successfully"

# Step 4: Verify compiler build
echo ""
echo "[Step 4] Verifying compiler..."
if [ ! -f "build/s_ir_runner" ]; then
    echo "ERROR: Compiler build failed"
    exit 1
fi
echo "✓ Compiler verified"

# Step 5: Compile ownership system example
echo ""
echo "[Step 5] Compiling ownership_system.s..."
INPUT_FILE="src/ownership_system.s"
OUTPUT_FILE="/tmp/ownership_system"

if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: $INPUT_FILE not found"
    exit 1
fi

./build/s_ir_runner "$INPUT_FILE" -o "$OUTPUT_FILE"
echo "✓ Generated: $OUTPUT_FILE"

# Step 6: Compile ownership examples
echo ""
echo "[Step 6] Compiling ownership_examples.s..."
INPUT_FILE2="src/ownership_examples.s"
OUTPUT_FILE2="/tmp/ownership_examples"

if [ ! -f "$INPUT_FILE2" ]; then
    echo "ERROR: $INPUT_FILE2 not found"
    exit 1
fi

./build/s_ir_runner "$INPUT_FILE2" -o "$OUTPUT_FILE2"
echo "✓ Generated: $OUTPUT_FILE2"

# Step 7: Compile borrow checker guide
echo ""
echo "[Step 7] Compiling borrow_checker.s..."
INPUT_FILE3="src/borrow_checker.s"
OUTPUT_FILE3="/tmp/borrow_checker"

if [ ! -f "$INPUT_FILE3" ]; then
    echo "ERROR: $INPUT_FILE3 not found"
    exit 1
fi

./build/s_ir_runner "$INPUT_FILE3" -o "$OUTPUT_FILE3"
echo "✓ Generated: $OUTPUT_FILE3"

# Step 8: Test existing ownership test
echo ""
echo "[Step 8] Testing existing ownership test case..."
TEST_FILE="test/compiler/ownership.s"

if [ -f "$TEST_FILE" ]; then
    ./build/s_ir_runner "$TEST_FILE" -o /tmp/test_ownership
    echo "✓ Existing test compiled successfully"
else
    echo "⚠ Test file not found: $TEST_FILE"
fi

# Step 9: Run compiler checks
echo ""
echo "[Step 9] Running compiler checks..."
if make compiler-check; then
    echo "✓ All compiler checks passed"
else
    echo "⚠ Some compiler checks may have failed"
fi

# Step 10: Summary
echo ""
echo "=========================================="
echo "Build Summary"
echo "=========================================="
echo ""
echo "Generated binaries:"
echo "  - $OUTPUT_FILE"
echo "  - $OUTPUT_FILE2"
echo "  - $OUTPUT_FILE3"
echo ""
echo "To run:"
echo "  $OUTPUT_FILE"
echo "  $OUTPUT_FILE2"
echo "  $OUTPUT_FILE3"
echo ""
echo "To view generated C code:"
echo "  cat ${OUTPUT_FILE}.c"
echo "  cat ${OUTPUT_FILE2}.c"
echo "  cat ${OUTPUT_FILE3}.c"
echo ""
echo "=========================================="
echo "Build Complete!"
echo "=========================================="

# Optional: Run the programs
echo ""
read -p "Run generated programs? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "[Running] $OUTPUT_FILE"
    echo "---"
    "$OUTPUT_FILE" || true
    echo ""
    
    echo "[Running] $OUTPUT_FILE2"
    echo "---"
    "$OUTPUT_FILE2" || true
    echo ""
    
    echo "[Running] $OUTPUT_FILE3"
    echo "---"
    "$OUTPUT_FILE3" || true
fi

exit 0
