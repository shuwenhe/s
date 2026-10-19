#!/usr/bin/env bash
# S 编译器自举诊断和执行脚本
# 使用方法: bash doc/bootstrap/diagnose-and-run.sh

set -euo pipefail

ROOT=${S_SOURCE_ROOT:-.}
AUDIT_DIR="$ROOT/.bootstrap/audit"
mkdir -p "$AUDIT_DIR"

echo "======================================================================"
echo "  S Compiler Bootstrap - Diagnosis and Execution"
echo "======================================================================"
echo ""

# Step 1: 冻结 Seed
echo "[Step 1] Freezing Seed Compiler..."
if [ ! -f "$ROOT/bin/s_seed" ]; then
    echo "ERROR: bin/s_seed not found. Run: make seed-compiler-bin"
    exit 1
fi

SEED_HASH=$(sha256sum "$ROOT/bin/s_seed" | cut -d' ' -f1)
SEED_COMMIT=$(cd "$ROOT" && git rev-parse HEAD)
echo "Seed SHA-256: $SEED_HASH"
echo "Seed Commit:  $SEED_COMMIT"
echo "$SEED_HASH" > "$AUDIT_DIR/seed.sha256"
echo "$SEED_COMMIT" > "$AUDIT_DIR/seed-commit.txt"

# Step 2: 冻结源码闭包
echo ""
echo "[Step 2] Freezing Source Closure..."
CLOSURE_FILE="$AUDIT_DIR/complete-closure.tsv"
S_SOURCE_ROOT="$ROOT" bash "$ROOT/src/cmd/dist/source_closure.sh" \
    src/cmd/compile/main.s > "$CLOSURE_FILE"
CLOSURE_COUNT=$(wc -l < "$CLOSURE_FILE")
CLOSURE_HASH=$(sha256sum "$CLOSURE_FILE" | cut -d' ' -f1)
echo "Closure Files: $CLOSURE_COUNT"
echo "Closure Hash:  $CLOSURE_HASH"
echo "$CLOSURE_HASH" > "$AUDIT_DIR/closure.sha256"

# Step 3: 运行自举脚本
echo ""
echo "[Step 3] Running Bootstrap Script..."
echo "Output: $AUDIT_DIR/stage1-run/"
echo ""

BOOTSTRAP_LOG="$AUDIT_DIR/bootstrap.log"
STAGE1_DIR="$AUDIT_DIR/stage1-run"
mkdir -p "$STAGE1_DIR"

# 运行自举，捕获所有输出
if bash "$ROOT/src/cmd/dist/native-bootstrap-no-manifest.sh" "$STAGE1_DIR" \
    > "$BOOTSTRAP_LOG" 2>&1; then
    echo "✅ Bootstrap completed successfully"
else
    EXIT_CODE=$?
    echo "❌ Bootstrap failed with exit code: $EXIT_CODE"
fi

# Step 4: 分析结果
echo ""
echo "[Step 4] Analyzing Results..."
echo ""

if grep -qi "error\|fail\|panic" "$BOOTSTRAP_LOG"; then
    echo "⚠️  ERRORS DETECTED:"
    grep -in "error\|fail\|panic" "$BOOTSTRAP_LOG" | head -5
    echo ""
    echo "First error location:"
    FIRST_ERROR=$(grep -in "error" "$BOOTSTRAP_LOG" | head -1)
    echo "$FIRST_ERROR"
    echo ""
    echo "Full log saved to: $BOOTSTRAP_LOG"
else
    echo "✅ No errors detected in bootstrap log"
fi

# Step 5: 检查产物
echo ""
echo "[Step 5] Checking Artifacts..."

if [ -f "$STAGE1_DIR/stage1" ]; then
    STAGE1_SIZE=$(stat -f%z "$STAGE1_DIR/stage1" 2>/dev/null || stat -c%s "$STAGE1_DIR/stage1")
    echo "✅ stage1 exists: $STAGE1_SIZE bytes"
    
    if file "$STAGE1_DIR/stage1" | grep -q "ELF"; then
        echo "✅ stage1 is valid ELF binary"
    else
        echo "⚠️  stage1 file type:"
        file "$STAGE1_DIR/stage1"
    fi
else
    echo "❌ stage1 not found"
fi

if [ -f "$STAGE1_DIR/stage1.ir" ]; then
    IR_SIZE=$(stat -f%z "$STAGE1_DIR/stage1.ir" 2>/dev/null || stat -c%s "$STAGE1_DIR/stage1.ir")
    echo "✅ stage1.ir exists: $IR_SIZE bytes"
else
    echo "❌ stage1.ir not found"
fi

# Step 6: 生成审计摘要
echo ""
echo "[Step 6] Generating Audit Summary..."

cat > "$AUDIT_DIR/P0-AUDIT.md" << 'EOF'
# P0 Bootstrap Audit Report

## Freeze Status

EOF

cat >> "$AUDIT_DIR/P0-AUDIT.md" << EOF
- Seed SHA-256: $SEED_HASH
- Seed Commit: $SEED_COMMIT
- Closure Files: $CLOSURE_COUNT
- Closure Hash: $CLOSURE_HASH
- Audit Date: $(date)
- Audit Directory: $AUDIT_DIR

## Bootstrap Execution

- Script: src/cmd/dist/native-bootstrap-no-manifest.sh
- Output Directory: $STAGE1_DIR
- Log File: bootstrap.log

## Status

EOF

if [ -f "$STAGE1_DIR/stage1" ] && [ -f "$STAGE1_DIR/stage1.ir" ]; then
    echo "✅ **Stage 1 Generation: SUCCESS**" >> "$AUDIT_DIR/P0-AUDIT.md"
else
    echo "❌ **Stage 1 Generation: FAILED**" >> "$AUDIT_DIR/P0-AUDIT.md"
fi

if grep -qi "error\|fail\|panic" "$BOOTSTRAP_LOG"; then
    echo "" >> "$AUDIT_DIR/P0-AUDIT.md"
    echo "## Detected Errors" >> "$AUDIT_DIR/P0-AUDIT.md"
    echo "" >> "$AUDIT_DIR/P0-AUDIT.md"
    grep -in "error" "$BOOTSTRAP_LOG" | head -10 >> "$AUDIT_DIR/P0-AUDIT.md"
fi

cat >> "$AUDIT_DIR/P0-AUDIT.md" << 'EOF'

## Next Steps

1. Review bootstrap.log for detailed error analysis
2. Identify FIRST RED error type (parser, symbol, codegen)
3. Create minimal reproduction case
4. Implement fix and re-run bootstrap
5. Repeat until Stage 1 generation succeeds

## Files

- bootstrap.log: Complete bootstrap output
- complete-closure.tsv: Source file closure manifest
- seed.sha256: Seed compiler hash
- P0-AUDIT.md: This report
EOF

echo "✅ Audit summary saved to: $AUDIT_DIR/P0-AUDIT.md"

echo ""
echo "======================================================================"
echo "  Audit Complete"
echo "======================================================================"
echo ""
echo "Key files:"
echo "  Log:      $BOOTSTRAP_LOG"
echo "  Closure:  $CLOSURE_FILE"
echo "  Summary:  $AUDIT_DIR/P0-AUDIT.md"
echo "  Artifacts: $STAGE1_DIR/"
echo ""
