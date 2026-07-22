#!/bin/bash

set -e

COMPILER="${COMPILER:-/Users/feifei/shuwen/s/bin/s}"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="/tmp/s_let_var_tests_$$"

mkdir -p "$OUTPUT_DIR"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  S Language Let/Var Feature Test Suite                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Test Directory: $TEST_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Compiler: $COMPILER"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

echo "📋 Test 1: Basic let/var functionality"
if $COMPILER "$TEST_DIR/let_var_basic.s" "$OUTPUT_DIR/let_var_basic.ir" >/dev/null 2>&1; then
    echo "  ✓ PASS: let_var_basic.s compiled successfully"
    ((TESTS_PASSED++))
else
    echo "  ✗ FAIL: let_var_basic.s compilation failed"
    ((TESTS_FAILED++))
fi
echo ""

echo "📋 Test 2: Immutability enforcement"
OUTPUT=$($COMPILER "$TEST_DIR/let_immutable.s" "$OUTPUT_DIR/let_immutable.ir" 2>&1)
if echo "$OUTPUT" | grep -q "symbol 'x' is immutable"; then
    echo "  ✓ PASS: Correctly rejected immutable reassignment"
    echo "    Error: $(echo "$OUTPUT" | grep "symbol 'x' is immutable")"
    ((TESTS_PASSED++))
else
    echo "  ✗ FAIL: Should reject immutable variable reassignment"
    echo "    Output: $OUTPUT"
    ((TESTS_FAILED++))
fi
echo ""

echo "📋 Test 3: Mutable variable functionality"
if $COMPILER "$TEST_DIR/var_mutable.s" "$OUTPUT_DIR/var_mutable.ir" >/dev/null 2>&1; then
    echo "  ✓ PASS: var_mutable.s compiled successfully"
    ((TESTS_PASSED++))
else
    echo "  ✗ FAIL: var_mutable.s compilation failed"
    ((TESTS_FAILED++))
fi
echo ""

echo "📋 Test 4: Comprehensive let/var integration"
if $COMPILER "$TEST_DIR/let_var_comprehensive.s" "$OUTPUT_DIR/let_var_comprehensive.ir" >/dev/null 2>&1; then
    echo "  ✓ PASS: let_var_comprehensive.s compiled successfully"
    echo "    Features: basic let, basic var, typed annotations, mixed usage, loops"
    ((TESTS_PASSED++))
else
    echo "  ✗ FAIL: let_var_comprehensive.s compilation failed"
    ((TESTS_FAILED++))
fi
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  TEST SUMMARY                                                  ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Total Tests: $((TESTS_PASSED + TESTS_FAILED))                                           ║"
echo "║  Passed: $TESTS_PASSED                                                   ║"
echo "║  Failed: $TESTS_FAILED                                                   ║"

if [ $TESTS_FAILED -eq 0 ]; then
    echo "║                                                                ║"
    echo "║  🎉 ALL TESTS PASSED 🎉                                        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"

    rm -rf "$OUTPUT_DIR"
    exit 0
else
    echo "║                                                                ║"
    echo "║  ⚠️  SOME TESTS FAILED                                         ║"
    echo "╚════════════════════════════════════════════════════════════════╝"

    echo ""
    echo "Output files retained in: $OUTPUT_DIR"
    exit 1
fi
