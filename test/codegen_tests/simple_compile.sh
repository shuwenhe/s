#!/bin/bash

# Simple Native Compiler for S Language
# Usage: ./simple_compile.sh <input.s> -o <output>

INPUT_FILE="$1"
OUTPUT_FILE="$3"

if [[ ! -f "$INPUT_FILE" ]] || [[ -z "$OUTPUT_FILE" ]]; then
    echo "Usage: simple_compile.sh <input.s> -o <output>"
    exit 1
fi

COMPILER="/home/shuwen/shuwen/s/bin/s_seed"
IR_TO_ASM="/home/shuwen/shuwen/s/test/codegen_tests/ir_to_asm.sh"

# Create unique temp file names
TEMP_PREFIX="${OUTPUT_FILE}_$(date +%s)"
TEMP_IR="${TEMP_PREFIX}.ir"
TEMP_ASM="${TEMP_PREFIX}.s"
TEMP_OBJ="${TEMP_PREFIX}.o"

echo "Step 1: Generating IR..."
"$COMPILER" "$INPUT_FILE" "$TEMP_IR"

echo "Step 2: Converting IR to assembly..."
bash "$IR_TO_ASM" "$TEMP_IR" "$TEMP_ASM"

echo "Step 3: Assembling..."
gcc -c "$TEMP_ASM" -o "$TEMP_OBJ" 2>&1 | grep -v "warning.*stack" || true

echo "Step 4: Linking..."
gcc "$TEMP_OBJ" -o "$OUTPUT_FILE" 2>&1 | grep -v "warning.*stack" || true

echo "Step 5: Cleanup..."
rm -f "$TEMP_IR" "$TEMP_ASM" "$TEMP_OBJ"

if [[ -x "$OUTPUT_FILE" ]]; then
    echo "✓ Success! Compiled to: $OUTPUT_FILE"
    echo "Testing..."
    "./$OUTPUT_FILE"
    echo "Return code: $?"
else
    echo "✗ Compilation failed or file not executable"
    exit 1
fi
