#!/bin/bash
# source_closure.sh - Robust dependency closure collection
# Iterative BFS implementation (no recursion, no pipe subshells)
# Can be run from any directory

set -e

ENTRY_FILE="${1:-.}"

# Determine PROJECT_ROOT
# Try multiple methods to find the root
if [ -d "$(dirname "$0")/src" ]; then
    # Running from project root or scripts/ subdirectory
    PROJECT_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || \
    PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
elif [ -d "./src" ]; then
    PROJECT_ROOT="$(pwd)"
elif [ -d "../src" ]; then
    PROJECT_ROOT="$(cd .. && pwd)"
else
    echo "ERROR: Cannot find project root (looking for ./src directory)" >&2
    exit 1
fi

SOURCE_ROOT="$PROJECT_ROOT/src"

# Temp files
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PKG_INDEX="$TMPDIR/pkg_index.txt"
SEEN_SET="$TMPDIR/seen.txt"
QUEUE_FILE="$TMPDIR/queue.txt"
RESULTS="$TMPDIR/results.txt"

touch "$PKG_INDEX" "$SEEN_SET" "$QUEUE_FILE" "$RESULTS"

# ============================================================
# build_package_index: pkg -> file mapping
# ============================================================
build_index() {
    local tmpfile="$TMPDIR/index_build.txt"
    > "$tmpfile"
    
    find "$SOURCE_ROOT" -name "*.s" -type f ! -name "*_test.s" 2>/dev/null | {
        while read -r file; do
            local pkg
            # Extract package name: "package PKGNAME" -> "PKGNAME"
            pkg=$(grep -m1 '^[[:space:]]*package ' "$file" 2>/dev/null | \
                  sed -E 's/^[[:space:]]*package[[:space:]]+([^[:space:]]+).*/\1/' || true)
            
            if [ -n "$pkg" ]; then
                echo "$pkg	$file" >> "$tmpfile"
            fi
        done
    }
    
    sort -u "$tmpfile" > "$PKG_INDEX" 2>/dev/null || true
    rm -f "$tmpfile"
}

# ============================================================
# lookup_package: Find file(s) providing a package
# ============================================================
lookup_package() {
    local pkg="$1"
    local exact_found=0
    
    # Exact match
    {
        while IFS=$'\t' read -r p f; do
            if [ "$p" = "$pkg" ]; then
                echo "$f"
                exact_found=1
            fi
        done
    } < "$PKG_INDEX"
    
    if [ "$exact_found" -eq 1 ]; then
        return 0
    fi
    
    # Hierarchical prefix (try longer prefixes first)
    local current="$pkg"
    while [ -n "$current" ]; do
        local prefix_found=0
        {
            while IFS=$'\t' read -r p f; do
                case "$p" in
                    "$current"*) 
                        echo "$f"
                        prefix_found=1
                        ;;
                esac
            done
        } < "$PKG_INDEX"
        
        if [ "$prefix_found" -eq 1 ]; then
            return 0
        fi
        
        # Shorten prefix
        if [ "${current#*.}" != "$current" ]; then
            current="${current%.*}"
        else
            break
        fi
    done
    
    return 1
}

# ============================================================
# Main: BFS traversal with explicit queue
# ============================================================
cd "$PROJECT_ROOT" || exit 1

# Normalize entry file path
if [ ! -f "$ENTRY_FILE" ]; then
    if [ -f "$PROJECT_ROOT/$ENTRY_FILE" ]; then
        ENTRY_FILE="$PROJECT_ROOT/$ENTRY_FILE"
    else
        # Try relative to current directory
        ENTRY_FILE="$(cd "$(dirname "$ENTRY_FILE")" 2>/dev/null && pwd)/$(basename "$ENTRY_FILE")" || {
            echo "ERROR: Entry file not found: ${1:-.}" >&2
            exit 1
        }
    fi
fi

# Build index
build_index

# Initialize queue
echo "$ENTRY_FILE" > "$QUEUE_FILE"

# BFS: Process queue until empty
count=0
limit=1000

while [ -s "$QUEUE_FILE" ]; do
    count=$((count + 1))
    if [ "$count" -gt "$limit" ]; then
        echo "ERROR: Exceeded iteration limit ($limit) - possible cycle" >&2
        exit 1
    fi
    
    # Extract first item from queue
    current_file=$(head -1 "$QUEUE_FILE")
    
    # Remove from queue (shift queue)
    tail -n +2 "$QUEUE_FILE" > "$QUEUE_FILE.tmp" 2>/dev/null || true
    mv "$QUEUE_FILE.tmp" "$QUEUE_FILE" 2>/dev/null || true
    
    # Skip if already seen
    if grep -Fxq "$current_file" "$SEEN_SET" 2>/dev/null; then
        continue
    fi
    
    # Mark as seen
    echo "$current_file" >> "$SEEN_SET"
    
    # Add to results
    echo "$current_file" >> "$RESULTS"
    
    # Extract imports and queue them
    {
        grep '^[[:space:]]*use ' "$current_file" 2>/dev/null || true
    } | {
        while read -r use_line; do
            pkg=$(echo "$use_line" | sed -E 's/^[[:space:]]*use[[:space:]]+([^[:space:]]+).*/\1/')
            
            # Skip empty or test packages
            if [ -z "$pkg" ] || [ "${pkg%_test}" != "$pkg" ]; then
                continue
            fi
            
            # Resolve to files
            resolved=$(lookup_package "$pkg" 2>/dev/null || true)
            
            if [ -n "$resolved" ]; then
                echo "$resolved" | {
                    while read -r target_file; do
                        # Skip test files
                        if [ -n "$target_file" ] && [ "${target_file%_test.s}" = "$target_file" ]; then
                            echo "$target_file" >> "$QUEUE_FILE"
                        fi
                    done
                }
            fi
        done
    }
done

# Output deduplicated results
if [ -f "$RESULTS" ]; then
    sort -u "$RESULTS" | sed "s|^$PROJECT_ROOT/||; s|^$PROJECT_ROOT||"
fi

