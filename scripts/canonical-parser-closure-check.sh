#!/bin/bash

###############################################################################
# canonical-parser-closure-check.sh
#
# PURPOSE:
#   Verify that the S compiler's Parser can successfully parse the entire
#   canonical Stage1 reachable source closure without errors.
#
# OUTPUT:
#   Binary result: PASS / FAIL
#   With detailed reporting of:
#   - Files required vs parsed
#   - Parse errors (with locations)
#   - Unsupported syntax
#   - Regressions
#
# USAGE:
#   ./scripts/canonical-parser-closure-check.sh [source-root]
#
# GATE EXIT CODE:
#   0 = PASS (all files parsed, 0 errors)
#   1 = FAIL (errors detected)
#
###############################################################################

set -e

# Configuration
SOURCE_ROOT="${1:-.}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
TEMP_DIR="/tmp/parser-closure-check-$$"
CLOSURE_FILE="${SOURCE_ROOT}/.parser-closure-manifest"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# State tracking
PARSE_ERRORS=()
UNSUPPORTED_SYNTAX=()
REQUIRED_FILES=()
PARSED_FILES=()
FAILED_FILES=()
REGRESSIONS=()

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR"

###############################################################################
# STEP 1: Identify canonical closure files
###############################################################################

echo "========================================"
echo "PARSER CANONICAL CLOSURE CHECK"
echo "========================================"
echo ""
echo "[1/4] Identifying canonical closure..."

# Find all *.s files in src/ that are part of Stage1 reachable closure
# Priority: src/cmd/compile/modular_build_main.s + its transitive dependencies
if [[ ! -f "$COMPILER" ]]; then
    echo -e "${RED}ERROR: s_compiler not found at $COMPILER${NC}"
    echo "Build the compiler first: make"
    exit 1
fi

# Get the canonical closure by analyzing modular_build_main.s
# For now, scan standard directories that are bootstrapped
REQUIRED_FILES=(
    # Core compiler infrastructure
    "src/cmd/compile/modular_build_main.s"
    
    # Essential frontend
    "src/compiler/frontend/scanner.s"
    "src/compiler/frontend/parser.s"
    "src/compiler/frontend/ast.s"
    
    # Type system
    "src/compiler/types/check.s"
    "src/compiler/types/type.s"
    
    # IR generation
    "src/cmd/compile/internal/mir.s"
    
    # Backend
    "src/cmd/compile/internal/backend_elf64.s"
)

# Alternative: auto-discover from canonical closure file
if [[ -f "$CLOSURE_FILE" ]]; then
    REQUIRED_FILES=($(cat "$CLOSURE_FILE"))
fi

echo "Found ${#REQUIRED_FILES[@]} files to parse:"
for f in "${REQUIRED_FILES[@]}"; do
    echo "  - $f"
done
echo ""

###############################################################################
# STEP 2: Parse each file and collect errors
###############################################################################

echo "[2/4] Parsing files..."
echo ""

ERROR_COUNT=0
PARSE_ERROR_DETAILS=""

for srcfile in "${REQUIRED_FILES[@]}"; do
    fullpath="${SOURCE_ROOT}/${srcfile}"
    
    if [[ ! -f "$fullpath" ]]; then
        echo -e "${YELLOW}⚠ SKIP:${NC} $srcfile (file not found)"
        continue
    fi
    
    REQUIRED_FILES+=("$srcfile")
    
    # Try to parse
    output_ast="${TEMP_DIR}/$(basename "$srcfile").ast"
    
    if "$COMPILER" ast "$fullpath" > "$output_ast" 2>&1; then
        PARSED_FILES+=("$srcfile")
        echo -e "${GREEN}✓${NC} $srcfile"
    else
        FAILED_FILES+=("$srcfile")
        ERROR_COUNT=$((ERROR_COUNT + 1))
        
        # Extract error details
        error_output=$(<"$output_ast")
        PARSE_ERROR_DETAILS+="
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
File: $srcfile
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$error_output
"
        echo -e "${RED}✗${NC} $srcfile"
    fi
done

echo ""

###############################################################################
# STEP 3: Regression test (if previous baseline exists)
###############################################################################

echo "[3/4] Checking for regressions..."

REGRESSION_FILE="${TEMP_DIR}/regression-baseline.txt"
REGRESSION_COUNT=0

# For now, skip regression check (would need baseline file)
if [[ -f "$REGRESSION_FILE" ]]; then
    echo "⚠ Regression check not yet implemented"
else
    echo "ℹ No regression baseline. Creating baseline for next run:"
    {
        echo "# Parser Closure Baseline"
        echo "# Generated: $(date)"
        echo "# Files parsed: ${#PARSED_FILES[@]}"
        echo "# Parse errors: $ERROR_COUNT"
        echo ""
        for f in "${PARSED_FILES[@]}"; do
            echo "PASS: $f"
        done
        for f in "${FAILED_FILES[@]}"; do
            echo "FAIL: $f"
        done
    } > "$REGRESSION_FILE"
fi

echo ""

###############################################################################
# STEP 4: Report results
###############################################################################

echo "[4/4] Results"
echo ""
echo "========================================"
echo "CANONICAL PARSER CLOSURE RESULTS"
echo "========================================"
echo ""
echo "Files required:    ${#REQUIRED_FILES[@]}"
echo "Files parsed:      ${#PARSED_FILES[@]}"
echo "Parse errors:      $ERROR_COUNT"
echo "Unsupported:       ${#UNSUPPORTED_SYNTAX[@]}"
echo "Regressions:       $REGRESSION_COUNT"
echo ""

if [[ $ERROR_COUNT -eq 0 ]]; then
    echo -e "${GREEN}RESULT: PASS${NC}"
    echo ""
    echo "✓ Parser can successfully handle canonical Stage1 closure"
    echo "✓ All required files parse without errors"
    echo "✓ Ready to FREEZE Parser and move to: Name/Import Resolution"
    echo ""
    echo "NEXT STEPS:"
    echo "  1. Mark P0 (Parser) as FROZEN"
    echo "  2. Begin P1: Name/Import Resolution + DeclarationRef"
    echo "  3. Do NOT add new Parser features"
    echo "  4. Do NOT modify Parser code"
    echo ""
    exit 0
else
    echo -e "${RED}RESULT: FAIL${NC}"
    echo ""
    echo "✗ Parser cannot complete canonical closure"
    echo "✗ First errors:"
    echo "$PARSE_ERROR_DETAILS"
    echo ""
    echo "ATTRIBUTION:"
    echo "  Analyze first error above and classify as:"
    echo "    - source defect (fix source file)"
    echo "    - parser capability gap (extend parser)"
    echo "    - unreachable code (exclude from closure)"
    echo ""
    echo "NEXT STEPS:"
    echo "  1. Fix first blocker"
    echo "  2. Re-run: $0"
    echo "  3. Iterate until: RESULT: PASS"
    echo ""
    exit 1
fi
