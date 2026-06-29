#!/bin/bash
# Test script for S compiler array syntax - moved to s/test

COMPILER="/Users/feifei/shuwen/s/bin/s"
TEST_DIR="/Users/feifei/shuwen/s/test/arrays"

echo "=== S Compiler Array Syntax Verification ==="
echo "Compiler: $COMPILER"
echo ""

# Test 1: Empty array
echo "Test 1: Empty typed array"
$COMPILER "$TEST_DIR/test_empty_array.s" /tmp/test_empty.ir 2>&1
echo ""

# Test 2: Single element
echo "Test 2: Single element array"
$COMPILER "$TEST_DIR/test_var_decl.s" /tmp/test_single.ir 2>&1
echo ""

# Test 3: Multi-element (THE CRITICAL TEST)
echo "Test 3: Multi-element array (CRITICAL FIX)"
$COMPILER "$TEST_DIR/test_var_multi.s" /tmp/test_multi.ir 2>&1
echo ""

# Test 4: Typed declaration
echo "Test 4: Typed array declaration"
$COMPILER "$TEST_DIR/test_typed_decl.s" /tmp/test_typed.ir 2>&1
echo ""

echo "=== Test Complete ==="
