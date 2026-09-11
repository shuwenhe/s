#!/bin/zsh
# source_closure.sh - Minimal, debuggable version
# Debug with: ZSH_DEBUG=1 ./source_closure.sh ...

set -e

ENTRY_FILE="${1:-.}"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="$PROJECT_ROOT/src"

# Use actual temp dir, not variable expansion
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PACKAGE_INDEX="$TMPDIR/pkg_index.txt"
SEEN_FILES="$TMPDIR/seen.txt"
RESULT_FILES="$TMPDIR/result.txt"
ERROR_LOG="$TMPDIR/errors.txt"

touch "$SEEN_FILES" "$RESULT_FILES" "$ERROR_LOG"

# Minimal package index builder (single pass, no subshell)
build_package_index() {
    local index="$1"
    > "$index"
    
    # Use find with explicit action to avoid subshell issues
    find "$SOURCE_ROOT" -name "*.s" -not -name "*_test.s" -print 2>/dev/null | while read -r file; do
        # Safe grep with error handling
        if [ -f "$file" ]; then
            package=$(grep -m 1 '^[[:space:]]*package ' "$file" 2>/dev/null | \
                      head -1 | sed 's/^[[:space:]]*package[[:space:]]\+\([^[:space:]]*\).*/\1/' || echo "")
            if [ ! -z "$package" ]; then
                echo "$package	${file#$PROJECT_ROOT/}"
            fi
        fi
    done >> "$index"
    
    # Sort afterwards (already in subshell)
    sort -u "$index" > "$index.tmp"
    mv "$index.tmp" "$index"
}

# Resolve package to files (simple version)
resolve_package() {
    local pkg="$1"
    local importer="$2"
    
    # Try exact match first
    grep -F "	" "$PACKAGE_INDEX" | while IFS=$'\t' read p f; do
        if [ "$p" = "$pkg" ]; then
            echo "$f"
        fi
    done
    
    # If no match, try longest prefix
    if [ $? -ne 0 ]; then
        local current="$pkg"
        while [ ! -z "$current" ]; do
            grep "^${current}[[:space:]]" "$PACKAGE_INDEX" 2>/dev/null | cut -f2- || true
            [ $? -eq 0 ] && return 0
            
            # Shorten package name
            if [[ "$current" == *.* ]]; then
                current="${current%.*}"
            else
                break
            fi
        done
        
        echo "ERROR: Unresolved package '$pkg' in $importer" >> "$ERROR_LOG"
        return 1
    fi
}

# Main recursive collection (with depth limit to catch infinite loops)
collect_sources() {
    local file="$1"
    local depth="${2:-0}"
    
    # Safety: max depth 50
    if [ "$depth" -gt 50 ]; then
        echo "ERROR: Max depth exceeded for $file" >> "$ERROR_LOG"
        return 1
    fi
    
    # Normalize path
    if [ ! -f "$file" ]; then
        if [ -f "$PROJECT_ROOT/$file" ]; then
            file="$PROJECT_ROOT/$file"
        else
            echo "ERROR: File not found: $file" >> "$ERROR_LOG"
            return 1
        fi
    fi
    
    # Check seen (literal match, no regex)
    if grep -Fxq "$file" "$SEEN_FILES" 2>/dev/null; then
        return 0
    fi
    
    # Mark seen
    echo "$file" >> "$SEEN_FILES"
    echo "$file" >> "$RESULT_FILES"
    
    # Extract uses from file
    grep '^[[:space:]]*use ' "$file" 2>/dev/null | while read -r use_line; do
        # Parse package name
        pkg=$(echo "$use_line" | sed -E 's/^[[:space:]]*use[[:space:]]+([^[:space:]]+).*/\1/')
        
        # Skip empty or test packages
        if [ -z "$pkg" ] || [[ "$pkg" == *_test ]]; then
            continue
        fi
        
        # Resolve and recurse
        target_files=$(resolve_package "$pkg" "$(basename $file)" 2>/dev/null || echo "")
        
        if [ ! -z "$target_files" ]; then
            echo "$target_files" | while read -r target; do
                if [ ! -z "$target" ] && [[ "$target" != *_test.s ]]; then
                    # Avoid subshell recursion
                    collect_sources "$PROJECT_ROOT/$target" $((depth + 1))
                fi
            done
        fi
    done
}

# Main
cd "$PROJECT_ROOT" || exit 1

# Verify entry
if [ ! -f "$ENTRY_FILE" ]; then
    echo "ERROR: Entry file not found: $ENTRY_FILE" >&2
    exit 1
fi

# Build index
build_package_index "$PACKAGE_INDEX"

# Collect closure (with debug output)
if [ ! -z "$ZSH_DEBUG" ]; then
    echo "Collecting closure from $ENTRY_FILE" >&2
fi

collect_sources "$ENTRY_FILE"

# Check errors
if [ -s "$ERROR_LOG" ]; then
    cat "$ERROR_LOG" >&2
    exit 1
fi

# Output results
if [ -f "$RESULT_FILES" ]; then
    cat "$RESULT_FILES" | while read -r f; do
        echo "${f#$PROJECT_ROOT/}"
    done
fi
