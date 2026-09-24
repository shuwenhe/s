#!/bin/bash

###############################################################################
# locate-canonical-line.sh
#
# Find which source file contains a specific line number in the canonical closure
# accounting for concatenated file line numbers.
#
# USAGE:
#   ./scripts/locate-canonical-line.sh <closure-file> <line-number>
#
###############################################################################

CLOSURE_FILE="$1"
TARGET_LINE="${2:-4304}"

if [[ ! -f "$CLOSURE_FILE" ]]; then
    echo "Error: Closure file not found: $CLOSURE_FILE"
    exit 1
fi

if [[ -z "$TARGET_LINE" ]]; then
    echo "Usage: $0 <closure-file> <line-number>"
    exit 1
fi

SOURCE_ROOT="${SOURCE_ROOT:-.}"

echo "Locating line $TARGET_LINE in canonical closure..."
echo "Closure file: $CLOSURE_FILE"
echo ""

CUMULATIVE_LINES=0
PREV_CUMULATIVE=0

while IFS= read -r srcfile; do
    if [[ -z "$srcfile" ]] || [[ "$srcfile" =~ ^# ]]; then
        continue
    fi
    
    fullpath="${SOURCE_ROOT}/${srcfile}"
    
    if [[ ! -f "$fullpath" ]]; then
        echo "⚠ File not found: $srcfile (skipping)"
        continue
    fi
    
    # Count lines in this file
    file_lines=$(wc -l < "$fullpath")
    CUMULATIVE_LINES=$((CUMULATIVE_LINES + file_lines))
    
    # Check if target line falls within this file
    if [[ $TARGET_LINE -le $CUMULATIVE_LINES ]]; then
        LOCAL_LINE=$((TARGET_LINE - PREV_CUMULATIVE))
        
        echo "=========================================="
        echo "FOUND: Line $TARGET_LINE"
        echo "=========================================="
        echo ""
        echo "File:         $srcfile"
        echo "Local line:   $LOCAL_LINE"
        echo "File size:    $file_lines lines"
        echo "Cumulative:   $CUMULATIVE_LINES lines"
        echo ""
        
        # Show context around the error
        start_line=$((LOCAL_LINE - 3))
        if [[ $start_line -lt 1 ]]; then
            start_line=1
        fi
        
        end_line=$((LOCAL_LINE + 3))
        if [[ $end_line -gt $file_lines ]]; then
            end_line=$file_lines
        fi
        
        echo "Context (lines $start_line-$end_line):"
        echo "---"
        sed -n "${start_line},${end_line}p" "$fullpath" | cat -n --v --tab=4 | sed "s/^     /$(printf '\033[0;32m')$start_line-$(printf '\033[0m') /"
        echo "---"
        echo ""
        echo "Error on line $LOCAL_LINE (column 10):"
        error_line=$(sed -n "${LOCAL_LINE}p" "$fullpath")
        echo ">>> $error_line"
        echo ""
        
        # Highlight the error position
        pos_prefix=$(printf '%0.s ' {1..12})
        echo "${pos_prefix}^"
        echo ""
        
        exit 0
    fi
    
    PREV_CUMULATIVE=$CUMULATIVE_LINES
done < "$CLOSURE_FILE"

echo "Error: Line $TARGET_LINE is beyond the closure range (max: $CUMULATIVE_LINES)"
exit 1
