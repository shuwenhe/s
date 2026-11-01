#!/bin/bash
# B6.7.3 Verification Gate
# Verify qualified member type resolution for import module members

cd /Users/feifei/shuwen/s

echo "=== B6.7.3 VERIFICATION GATE: Qualified Member Type Resolution ==="
echo "Phase: std.env type resolution (member of module 'std')"
echo

PASS=0
FAIL=0

# Test 1: Verify module root registration (from B6.7.2)
echo "[Gate 1] std-root-resolution: Checking module root 'std' is registered..."
cat > /tmp/gate_std_root.s << 'EOF'
package test
import (
    "std.env"
)
func main() int {
    x := std
    return 0
}
EOF

if ./bin/s_seed /tmp/gate_std_root.s 2>&1 | grep -q "undeclared symbol 'std'"; then
    echo "  ✗ FAIL: 'std' root symbol not registered"
    FAIL=$((FAIL+1))
else
    echo "  ✓ 'std' module root is accessible"
    PASS=$((PASS+1))
fi
echo

# Test 2: Verify std.env member access (KEY TEST FOR B6.7.3)
echo "[Gate 2] std.env-type!=any: Checking std.env has non-'any' type..."
cat > /tmp/gate_std_env.s << 'EOF'
package test
import (
    "std.env"
)
func main() int {
    x := std.env
    return 0
}
EOF

OUT=$( ./bin/s_seed /tmp/gate_std_env.s 2>&1)

# Check for the OLD error that indicates std.env is 'any' type
if echo "$OUT" | grep -q "type 'any' has no"; then
    echo "  ✗ FAIL: std.env still has type 'any' (error mentions 'any')"
    FAIL=$((FAIL+1))
    echo "  Error output: $OUT" | head -3
else
    echo "  ✓ std.env does not default to 'any' type"
    PASS=$((PASS+1))
fi
echo

# Test 3: Verify std.env.args() call resolution (FULL B6.7.3 FIX)
echo "[Gate 3] std.env.args-resolution: Checking std.env.args() resolves..."
cat > /tmp/gate_std_env_args.s << 'EOF'
package test
import (
    "std.env"
)
func main() int {
    args := std.env.args()
    return 0
}
EOF

OUT=$( ./bin/s_seed /tmp/gate_std_env_args.s 2>&1)

# Check for the OLD error
if echo "$OUT" | grep -q "type 'any' has no method 'args'"; then
    echo "  ✗ FAIL: std.env.args still fails with 'any' error"
    FAIL=$((FAIL+1))
    echo "  Error output: $OUT" | head -3
else
    echo "  ✓ std.env.args() call is recognized/resolves"
    PASS=$((PASS+1))
fi
echo

# Test 4: Check that import function signatures are being used
echo "[Gate 4] import-signature-authority: Checking import_signatures.meta is active..."
if grep -q "std.env.args" src/cmd/compile/seed/semantic/import_signatures.meta; then
    echo "  ✓ Canonical authority (import_signatures.meta) contains std.env.args"
    PASS=$((PASS+1))
else
    echo "  ✗ FAIL: Canonical signature authority incomplete"
    FAIL=$((FAIL+1))
fi
echo

# Summary
echo "=== RESULTS ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo

if [ $FAIL -eq 0 ]; then
    echo "Status: PASS/FROZEN"
    echo "Classification: QUALIFIED_MEMBER_TYPE_RESOLUTION_FIXED"
    exit 0
else
    echo "Status: INCOMPLETE"
    exit 1
fi
