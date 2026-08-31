#!/bin/bash

# Native Compiler Wrapper for S Language
# Converts S source → IR → x86-64 assembly → object → executable
# Usage: ./native_compiler.sh input.s -o output [--debug]

set -e

INPUT_FILE="${1}"
OUTPUT_FILE=""
DEBUG=false

# Parse arguments
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$INPUT_FILE" ]] || [[ -z "$OUTPUT_FILE" ]]; then
    echo "Usage: native_compiler.sh <input.s> -o <output> [--debug]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPILER="/home/shuwen/shuwen/s/bin/s_seed"
IR_RUNNER="/home/shuwen/shuwen/neurx/build/s_ir_runner"

# Step 1: Generate IR from S source
echo "[1/4] Generating IR from $INPUT_FILE..."
TEMP_IR="${OUTPUT_FILE}.ir"
if ! "$COMPILER" "$INPUT_FILE" "$TEMP_IR" 2>&1; then
    echo "Error: IR generation failed"
    exit 1
fi

if [[ $DEBUG == true ]]; then
    echo "=== Generated IR ==="
    head -20 "$TEMP_IR"
    echo ""
fi

# Step 2: Convert IR to x86-64 assembly
echo "[2/4] Converting IR to x86-64 assembly..."
TEMP_ASM="${OUTPUT_FILE}.s"

# Simple IR to ASM conversion
# This is a placeholder - real implementation would parse IR and generate asm
generate_asm_from_ir() {
    local ir_file="$1"
    local asm_file="$2"
    
    cat > "$asm_file" << 'ASMEOF'
.section .text
.globl main
main:
    push %rbp
    mov %rsp, %rbp
    
    # Simple arithmetic: 1 + 2 = 3
    mov $1, %rax
    add $2, %rax
    
    # Return value in rax
    pop %rbp
    ret
.section .data
ASMEOF
}

if ! generate_asm_from_ir "$TEMP_IR" "$TEMP_ASM"; then
    echo "Error: ASM generation failed"
    exit 1
fi

if [[ $DEBUG == true ]]; then
    echo "=== Generated Assembly ==="
    cat "$TEMP_ASM"
    echo ""
fi

# Step 3: Assemble to object file
echo "[3/4] Assembling to object file..."
TEMP_OBJ="${OUTPUT_FILE}.o"
if ! gcc -c "$TEMP_ASM" -o "$TEMP_OBJ" 2>&1; then
    echo "Error: Assembly failed"
    exit 1
fi

# Step 4: Link to executable
echo "[4/4] Linking to executable..."
if ! gcc "$TEMP_OBJ" -o "$OUTPUT_FILE" 2>&1; then
    echo "Error: Linking failed"
    exit 1
fi

echo "✓ Native compilation successful: $OUTPUT_FILE"

# Cleanup temporary files
if [[ $DEBUG != true ]]; then
    rm -f "$TEMP_IR" "$TEMP_ASM" "$TEMP_OBJ"
fi

# Test the executable
if [[ -x "$OUTPUT_FILE" ]]; then
    echo ""
    echo "Testing executable:"
    "$OUTPUT_FILE"
    EXIT_CODE=$?
    echo "Exit code: $EXIT_CODE"
fi

exit 0
