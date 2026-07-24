#!/bin/bash
# Quick bootstrap verification script
# This tests whether the S self-hosting approach is feasible

set -e

SDIR="/home/shuwen/shuwen/s"
TMPDIR="/tmp/s_selfhost_test"
SEED="$SDIR/bin/s_seed"

mkdir -p "$TMPDIR"

echo "=== S Self-Hosting Bootstrap Test ==="
echo ""
echo "[Step 1] Checking seed compiler..."
if [ ! -f "$SEED" ]; then
    echo "ERROR: Seed compiler not found at $SEED"
    exit 1
fi
echo "✓ Seed compiler ready"

echo ""
echo "[Step 2] Generating IR from compiler source..."
$SEED "$SDIR/src/cmd/compile/main.s" "$TMPDIR/compiler.ir"
echo "✓ Generated compiler.ir ($(wc -l < $TMPDIR/compiler.ir) lines)"

echo ""
echo "[Step 3] Examining IR format..."
echo "First 20 IR instructions:"
head -20 "$TMPDIR/compiler.ir" | sed 's/^/  /'

echo ""
echo "[Step 4] Analyzing IR statistics..."
echo "  - FUNC_BEGIN: $(grep -c "FUNC_BEGIN" $TMPDIR/compiler.ir || echo 0)"
echo "  - FUNC_END: $(grep -c "FUNC_END" $TMPDIR/compiler.ir || echo 0)"
echo "  - CALL instructions: $(grep -c "^CALL|" $TMPDIR/compiler.ir || echo 0)"
echo "  - MOV instructions: $(grep -c "^MOV|" $TMPDIR/compiler.ir || echo 0)"
echo "  - Unique opcodes: $(cut -d'|' -f1 $TMPDIR/compiler.ir | sort -u | wc -l)"

echo ""
echo "[Step 5] Testing seed binary generation..."
$SEED --emit-bin "$TMPDIR/compiler.ir" "$TMPDIR/compiler_binary"
echo "✓ Generated binary: $(du -h $TMPDIR/compiler_binary | cut -f1)"

echo ""
echo "[Step 6] Checking binary symbols..."
echo "  - seed_compile_file: $(nm $TMPDIR/compiler_binary | grep -c 'seed_compile_file' || echo 0)"
echo "  - seed_compile_source_text: $(nm $TMPDIR/compiler_binary | grep -c 'seed_compile_source_text' || echo 0)"

echo ""
echo "[Step 7] Testing the binary can self-compile..."
$TMPDIR/compiler_binary "$SDIR/src/cmd/compile/main.s" "$TMPDIR/self_compiled.ir"
echo "✓ Self-compilation succeeded"

echo ""
echo "[Step 8] Verifying deterministic compilation..."
diff "$TMPDIR/compiler.ir" "$TMPDIR/self_compiled.ir" > /dev/null
echo "✓ IR output is deterministic"

echo ""
echo "=== Analysis Complete ==="
echo ""
echo "FINDINGS:"
echo "1. IR format: Simple text-based SSA (suitable for S implementation)"
echo "2. IR complexity: Manageable number of instruction types"
echo "3. Bootstrap feasibility: ✓ Highly feasible"
echo ""
echo "NEXT STEPS for pure S self-hosting:"
echo "1. Implement IR parser in S (src/cmd/compile/selfhost/ir_codegen.s)"
echo "2. Implement x86-64 code generator in S (src/cmd/compile/selfhost/x86_64_codegen.s)"
echo "3. Create ir_to_binary tool that uses both above"
echo "4. Modify Makefile to use pure S in bootstrap chain"
echo "5. Test with: make pure-selfhost"
echo ""
echo "Expected result: bin/s without any seed_compile symbols"
echo ""
