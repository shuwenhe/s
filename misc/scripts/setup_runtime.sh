#!/bin/bash
set -euo pipefail

# S Compiler Runtime Fix Script
# This script ensures the S compiler runtime environment is properly set up

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo "🔧 S Compiler Runtime Setup"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Resolve the repository root from the script location so the installer
# works regardless of the checkout path.
S_ROOT="$(cd "${SCRIPT_DIR}" && pwd)"
INSTALL_DIR="$S_ROOT/.local/bin"

# Step 1: Verify S compiler source files exist
echo "▶ Checking S compiler source files..."
REQUIRED_FILES=(
    "src/cmd/compile/seed/s_seed.c"
    "src/cmd/compile/seed/bootstrap/bootstrap.c"
    "src/cmd/compile/seed/lexical/lexer.c"
    "src/cmd/compile/seed/error/error.c"
    "src/cmd/compile/seed/syntax/parser.c"
    "src/cmd/compile/seed/semantic/analyzer.c"
    "src/cmd/compile/seed/intermediate/ir.c"
    "src/cmd/compile/seed/code/generator.c"
    "src/cmd/compile/seed/code/native_backend.c"
    "src/cmd/compile/seed/runtime/runtime.c"
)

cd "$S_ROOT"

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ Missing: $file"
        exit 1
    fi
done

echo "✓ All source files found"
echo ""

# Step 2: Compile S compiler
echo "▶ Compiling S compiler..."
ARCH=$(uname -m)
TIMESTAMP=$(date +%Y%m%d%H%M%S)

case "$ARCH" in
    arm64|aarch64)
        OUT_BIN="$S_ROOT/bin/s_arm64_${TIMESTAMP}"
        echo "  Architecture: ARM64"
        ;;
    x86_64)
        OUT_BIN="$S_ROOT/bin/s_x86_64_${TIMESTAMP}"
        echo "  Architecture: x86_64"
        ;;
    *)
        echo "  ✗ Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

mkdir -p "$S_ROOT/bin"

echo "  Compiling to: $OUT_BIN"
gcc -std=c11 -Wall -Wextra -Werror \
    -o "$OUT_BIN" \
    src/cmd/compile/seed/s_seed.c \
    src/cmd/compile/seed/bootstrap/bootstrap.c \
    src/cmd/compile/seed/lexical/lexer.c \
    src/cmd/compile/seed/error/error.c \
    src/cmd/compile/seed/syntax/parser.c \
    src/cmd/compile/seed/semantic/analyzer.c \
    src/cmd/compile/seed/intermediate/ir.c \
    src/cmd/compile/seed/code/generator.c \
    src/cmd/compile/seed/code/native_backend.c \
    src/cmd/compile/seed/runtime/runtime.c

chmod +x "$OUT_BIN"
echo "✓ Compilation successful"
echo ""

# Step 3: Install to .local/bin
echo "▶ Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp "$OUT_BIN" "$INSTALL_DIR/s"
chmod +x "$INSTALL_DIR/s"

echo "✓ Installation successful"
echo ""

# Step 4: Verify installation
echo "▶ Verifying installation..."
if [ -x "$INSTALL_DIR/s" ]; then
    echo "✓ Compiler executable verified"
else
    echo "✗ Compiler not executable"
    exit 1
fi

# Try a simple compile test
echo ""
echo "▶ Testing compiler..."
TEST_FILE="/tmp/test_s_compile_$$.s"
cat > "$TEST_FILE" << 'EOF'
package main

use std.io

func main() {
    io.println("S compiler is working!")
}
EOF

TEST_IR="/tmp/test_s_compile_$$.ir"
if "$INSTALL_DIR/s" "$TEST_FILE" "$TEST_IR" 2>&1 | head -5; then
    if [ -f "$TEST_IR" ]; then
        echo "✓ Test compilation successful"
        rm -f "$TEST_FILE" "$TEST_IR"
    else
        echo "✗ IR file not generated"
        exit 1
    fi
else
    echo "✗ Compilation test failed"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✓ S Compiler setup complete!"
echo "  Binary: $INSTALL_DIR/s"
echo "════════════════════════════════════════════════════════════════"
