#!/bin/bash
set -e

BOOTSTRAP_DIR="$1"
if [ -z "$BOOTSTRAP_DIR" ]; then
    BOOTSTRAP_DIR="/tmp/s_bootstrap_hosted"
fi

mkdir -p "$BOOTSTRAP_DIR"
cd "$BOOTSTRAP_DIR"

SEED_COMPILER="$PWD/../src/cmd/compile/seed/s_new"
COMPILER_SOURCE="$PWD/../src/cmd/compile/internal/compiler/main.s"

echo "=== S Compiler Bootstrap (Hosted Pathway) ==="
echo "Bootstrap directory: $BOOTSTRAP_DIR"
echo "Seed compiler: $SEED_COMPILER"
echo "Compiler source: $COMPILER_SOURCE"
echo ""

# Step 1: Compile compiler source to IR with Seed
echo "[1/6] Compiling full compiler source to IR with Seed..."
if ! "$SEED_COMPILER" "$COMPILER_SOURCE" stage1.ir 2>&1; then
    echo "ERROR: Seed failed to compile compiler source"
    exit 1
fi
if [ ! -f stage1.ir ]; then
    echo "ERROR: stage1.ir not generated"
    exit 1
fi
echo "✓ stage1.ir generated ($(wc -c < stage1.ir) bytes)"
echo ""

# Step 2: Generate hosted Stage2 binary from IR
echo "[2/6] Generating hosted Stage2 binary from IR..."
if ! "$SEED_COMPILER" --emit-hosted-program stage1.ir stage2_hosted 2>&1; then
    echo "ERROR: Failed to generate hosted Stage2"
    exit 1
fi
if [ ! -f stage2_hosted ]; then
    echo "ERROR: stage2_hosted not generated"
    exit 1
fi
file stage2_hosted
chmod +x stage2_hosted
echo "✓ Stage2 (hosted) binary generated"
echo ""

# Step 3: Use Stage2 to compile compiler source to stage2.ir
echo "[3/6] Using Stage2 to compile compiler source to stage2.ir..."
if ! ./stage2_hosted "$COMPILER_SOURCE" stage2.ir 2>&1; then
    echo "ERROR: Stage2 failed to compile compiler source"
    echo "This might mean Stage2 still has parsing limitations"
    exit 1
fi
if [ ! -f stage2.ir ]; then
    echo "ERROR: stage2.ir not generated"
    exit 1
fi
echo "✓ stage2.ir generated ($(wc -c < stage2.ir) bytes)"
echo ""

# Step 4: Generate native Stage3 binary from stage2.ir
echo "[4/6] Generating native Stage3 binary from stage2.ir..."
if ! "$SEED_COMPILER" --emit-standalone-amd64 stage2.ir stage3_native 2>&1; then
    echo "ERROR: Failed to generate native Stage3"
    exit 1
fi
if [ ! -f stage3_native ]; then
    echo "ERROR: stage3_native not generated"
    exit 1
fi
file stage3_native
chmod +x stage3_native
echo "✓ Stage3 (native AMD64) binary generated"
echo ""

# Step 5: Use Stage3 to compile compiler source to stage3.ir
echo "[5/6] Using Stage3 to compile compiler source to stage3.ir..."
if ! ./stage3_native "$COMPILER_SOURCE" stage3.ir 2>&1; then
    echo "ERROR: Stage3 failed to compile compiler source"
    exit 1
fi
if [ ! -f stage3.ir ]; then
    echo "ERROR: stage3.ir not generated"
    exit 1
fi
echo "✓ stage3.ir generated ($(wc -c < stage3.ir) bytes)"
echo ""

# Step 6: Verify bootstrap success
echo "[6/6] Verifying bootstrap (stage2.ir == stage3.ir)..."
if diff -q stage2.ir stage3.ir > /dev/null; then
    echo "✓✓✓ BOOTSTRAP SUCCESSFUL ✓✓✓"
    echo ""
    echo "Bootstrap artifacts:"
    echo "  Stage1 (Seed)    IR: stage1.ir"
    echo "  Stage2 (Hosted)  Binary: stage2_hosted"
    echo "  Stage2 (Hosted)  IR: stage2.ir"
    echo "  Stage3 (Native)  Binary: stage3_native"
    echo "  Stage3 (Native)  IR: stage3.ir"
    echo ""
    echo "✓ S compiler has achieved self-hosting!"
    echo "  Stage2 (hosted) compiled Stage3 (native)"
    echo "  Stage3 validates: Stage2 output == Stage3 output"
    exit 0
else
    echo "ERROR: Bootstrap failed - stage2.ir and stage3.ir differ"
    echo "First difference:"
    diff stage2.ir stage3.ir | head -20
    exit 1
fi
