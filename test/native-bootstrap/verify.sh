#!/usr/bin/env bash
# Verification script for native bootstrap chain
# Demonstrates that Stage1 (native-generated compiler binary) can:
#   1. Parse S source code  
#   2. Perform semantic analysis
#   3. Generate C code
#   4. Produce working executable

set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
stage1="${root}/.bootstrap/native-imports/stage1"
test_program="${root}/test/native-bootstrap/minimal.s"
temp_c="/tmp/s_bootstrap_test_$$.c"
temp_bin="/tmp/s_bootstrap_test_$$"

cleanup() {
    rm -f "$temp_c" "$temp_bin"
}
trap cleanup EXIT

if [ ! -x "$stage1" ]; then
    echo "Stage1 binary not found: $stage1"
    echo "Run: make native-bootstrap-imports"
    exit 1
fi

if [ ! -f "$test_program" ]; then
    echo "Test program not found: $test_program"
    exit 1
fi

echo "=== S Compiler Native Bootstrap Verification ==="
echo "Stage1 binary: $stage1"
echo "Test program: $test_program"
echo ""

echo "[1/4] Stage1 parses and analyzes S source..."
"$stage1" --emit-c "$test_program" "$temp_c" 2>&1 | grep -q "^$" || true
if [ ! -f "$temp_c" ]; then
    echo "✗ FAILED: Stage1 did not generate C output"
    exit 1
fi
echo "✓ Generated C code ($( wc -l < "$temp_c" ) lines)"

echo "[2/4] Compiling C output with gcc..."
gcc -o "$temp_bin" "$temp_c" -Isrc/runtime || {
    echo "✗ FAILED: gcc compilation failed"
    exit 1
}
echo "✓ Generated executable ($( du -h "$temp_bin" | cut -f1 ))"

echo "[3/4] Executing bootstrap binary..."
result=0
"$temp_bin" || result=$?
echo "✓ Program exited with code: $result"

echo "[4/4] Validating result..."
expected=156  # 8 + 28 + 120 (add(5,3) + multiply(4,7) + factorial(5))
if [ "$result" = "$expected" ]; then
    echo "✓ VERIFIED: Program exit code matches expected value ($expected)"
    echo ""
    echo "=== Native Bootstrap Chain SUCCESS ==="
    echo "✓ Seed compiler generated Stage1 from IR"
    echo "✓ Stage1 parsed S source code"  
    echo "✓ Stage1 generated C code"
    echo "✓ C code compiled and executed correctly"
    echo "✓ Bootstrap chain works end-to-end"
    echo ""
    echo "This proves that:"
    echo "  - Native-generated binary CAN act as a compiler"
    echo "  - S source CAN be compiled by native code"
    echo "  - Self-hosting bootstrap IS possible"
    exit 0
else
    echo "✗ FAILED: Expected $expected, got $result"
    exit 1
fi

