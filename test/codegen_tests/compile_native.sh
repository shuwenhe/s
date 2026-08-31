#!/bin/bash

# Complete Native Compilation Pipeline for S Language
# Converts S source → IR → x86-64 assembly → object → executable
# Usage: ./compile_native.sh <input.s> -o <output> [--debug] [--keep-temps]

INPUT_FILE="${1}"
OUTPUT_FILE=""
DEBUG=false
KEEP_TEMPS=false

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
        --keep-temps)
            KEEP_TEMPS=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$INPUT_FILE" ]] || [[ -z "$OUTPUT_FILE" ]]; then
    echo "❌ Usage: compile_native.sh <input.s> -o <output> [--debug] [--keep-temps]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPILER="/home/shuwen/shuwen/s/bin/s_seed"
IR_TO_ASM_SCRIPT="$SCRIPT_DIR/ir_to_asm.sh"

# Verify tools exist
if [[ ! -x "$COMPILER" ]]; then
    echo "❌ Error: S compiler not found at $COMPILER"
    exit 1
fi

if [[ ! -x "$IR_TO_ASM_SCRIPT" ]]; then
    echo "❌ Error: IR to ASM converter not found at $IR_TO_ASM_SCRIPT"
    exit 1
fi

# Temporary file paths
TEMP_IR="${OUTPUT_FILE}.ir.tmp"
TEMP_ASM="${OUTPUT_FILE}.s.tmp"
TEMP_OBJ="${OUTPUT_FILE}.o.tmp"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}[1/4]${NC} Generating IR from $INPUT_FILE..."
if ! "$COMPILER" "$INPUT_FILE" "$TEMP_IR" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: IR generation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ IR generated${NC}"

if [[ $DEBUG == true ]]; then
    echo -e "${BLUE}=== IR Content (first 20 lines) ===${NC}"
    head -20 "$TEMP_IR"
    echo ""
fi

echo -e "${BLUE}[2/4]${NC} Converting IR to x86-64 assembly..."
if ! bash "$IR_TO_ASM_SCRIPT" "$TEMP_IR" "$TEMP_ASM" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: IR to ASM conversion failed${NC}"
    rm -f "$TEMP_IR" "$TEMP_ASM" "$TEMP_OBJ"
    exit 1
fi
echo -e "${GREEN}✓ Assembly generated${NC}"

if [[ $DEBUG == true ]]; then
    echo -e "${BLUE}=== Assembly (first 30 lines) ===${NC}"
    head -30 "$TEMP_ASM"
    echo ""
fi

echo -e "${BLUE}[3/4]${NC} Assembling to object file..."
gcc -c "$TEMP_ASM" -o "$TEMP_OBJ" 2>&1 | grep -v "warning.*stack" || true
if [[ ! -f "$TEMP_OBJ" ]]; then
    echo -e "${RED}❌ Error: Assembly failed${NC}"
    rm -f "$TEMP_IR" "$TEMP_ASM" "$TEMP_OBJ"
    exit 1
fi
echo -e "${GREEN}✓ Object file created${NC}"

echo -e "${BLUE}[4/4]${NC} Linking to executable..."
gcc "$TEMP_OBJ" -o "$OUTPUT_FILE" 2>&1 | grep -v "warning.*stack" || true
if [[ ! -f "$OUTPUT_FILE" ]]; then
    echo -e "${RED}❌ Error: Linking failed${NC}"
    rm -f "$TEMP_IR" "$TEMP_ASM" "$TEMP_OBJ"
    exit 1
fi
echo -e "${GREEN}✓ Executable created${NC}"

echo -e "${GREEN}✅ Native compilation successful: $OUTPUT_FILE${NC}"
echo ""

# Cleanup temporary files
if [[ $KEEP_TEMPS != true ]]; then
    rm -f "$TEMP_IR" "$TEMP_ASM" "$TEMP_OBJ"
else
    echo "Temporary files kept:"
    echo "  - IR: $TEMP_IR"
    echo "  - ASM: $TEMP_ASM"
    echo "  - OBJ: $TEMP_OBJ"
fi

# Show file info
echo "Output file info:"
file "$OUTPUT_FILE" | sed 's/^/  /'

# Test if executable
if [[ -x "$OUTPUT_FILE" ]]; then
    echo ""
    echo "Testing executable:"
    if "$OUTPUT_FILE" >/dev/null 2>&1; then
        EXIT_CODE=$?
    else
        EXIT_CODE=$?
    fi
    echo "  Return value: $EXIT_CODE"
fi

exit 0
