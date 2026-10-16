#!/bin/bash
# gen_package_index.sh - Generate s-package-index.tsv from source files
# Used by modular compiler to resolve package imports

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ROOT="$PROJECT_ROOT/src"
OUTPUT="${1:-$PROJECT_ROOT/scripts/s-package-index.tsv}"

# Temp file
TMPINDEX=$(mktemp)
trap "rm -f $TMPINDEX" EXIT

# ============================================================
# Scan source files and extract package declarations
# ============================================================
echo "Scanning source files for package declarations..." >&2

> "$TMPINDEX"

find "$SOURCE_ROOT" -name "*.s" -type f ! -name "*_test.s" 2>/dev/null > "$TMPINDEX.files" || true

{
    while read -r file; do
        # Extract package name from "package PKGNAME"
        pkg=$(grep -m1 '^[[:space:]]*package ' "$file" 2>/dev/null | \
              sed -E 's/^[[:space:]]*package[[:space:]]+([^[:space:]]+).*/\1/' || true)
        
        if [ -n "$pkg" ]; then
            # Format: PACKAGE_NAME<TAB>RELATIVE_PATH
            relpath="${file#$PROJECT_ROOT/}"
            echo "$pkg	$relpath"
        fi
    done < "$TMPINDEX.files"
} >> "$TMPINDEX"

rm -f "$TMPINDEX.files"

# Sort and deduplicate
sort -u "$TMPINDEX" > "$OUTPUT" 2>/dev/null || true

echo "Generated package index: $OUTPUT" >&2
echo "Packages: $(wc -l < "$OUTPUT") entries" >&2

# Verify
if [ ! -s "$OUTPUT" ]; then
    echo "ERROR: Failed to generate package index" >&2
    exit 1
fi

exit 0
