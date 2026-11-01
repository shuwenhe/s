#!/bin/sh
# Gate for Phase 1.6.3: local-variable-binding with source-dependent execution
# 
# Proves that:
# 1. Local variable declarations (x := expr) are recognized
# 2. Local variable references work correctly
# 3. Different source values produce different runtime behavior
#
# This prevents "fake green" - i.e., verification that binding truly affects
# the generated native code execution, not just syntax parsing.

set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
compiler=${1:?usage: stage1-local-binding-execution-check.sh COMPILER}
test -x "$compiler"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "🧪 Phase 1.6.3 - Local Variable Binding + Execution Verification"
echo ""

# Test cases: (fixture_file, expected_exit_code)
test_cases="
test/delta-fixtures/delta-003-main-return-only.s:0
test/delta-fixtures/delta-009-return-expr.s:42
test/delta-fixtures/delta-010-local-binding-17.s:17
test/delta-fixtures/delta-011-local-binding-29.s:29
test/delta-fixtures/delta-012-binding-chain.s:17
test/delta-fixtures/delta-013-binding-chain-99.s:99
"

passed=0
failed=0

echo "Test Suite:"
echo "──────────────────────────────────────────────────────────────"

while IFS=: read -r fixture expected_exit; do
    [ -z "$fixture" ] && continue
    
    basename_fixture=$(basename "$fixture")
    out="$work/${basename_fixture%.s}"
    
    # Attempt compilation
    compile_status=0
    "$compiler" build "$fixture" -o "$out" > "$work/compile.log" 2>&1 || compile_status=$?
    
    if [ "$compile_status" -ne 0 ]; then
        echo "❌ $basename_fixture (COMPILATION FAILED)"
        echo "   Error: $(cat "$work/compile.log" | head -1)"
        failed=$((failed + 1))
        continue
    fi
    
    if [ ! -f "$out" ] || [ ! -x "$out" ]; then
        echo "❌ $basename_fixture (OUTPUT NOT EXECUTABLE)"
        failed=$((failed + 1))
        continue
    fi
    
    # Attempt execution
    exec_status=0
    "$out" > "$work/run.log" 2>&1 || exec_status=$?
    
    if [ "$exec_status" -eq "$expected_exit" ]; then
        echo "✅ $basename_fixture (exit=$expected_exit)"
        passed=$((passed + 1))
    else
        echo "❌ $basename_fixture (WRONG EXIT CODE)"
        echo "   Expected: $expected_exit"
        echo "   Got: $exec_status"
        failed=$((failed + 1))
    fi
done <<EOF
$test_cases
EOF

echo ""
echo "──────────────────────────────────────────────────────────────"
echo "Results: $passed passed, $failed failed"
echo ""

if [ "$failed" -eq 0 ]; then
    echo "✅ Gate PASS: local-variable-binding with source-dependent execution verified"
    exit 0
else
    echo "❌ Gate FAIL: $failed test(s) failed"
    exit 1
fi
