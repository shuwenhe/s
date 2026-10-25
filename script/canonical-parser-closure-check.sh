#!/usr/bin/env bash
# Check lexer -> parser -> AST for the sources used by make compiler.
# Name resolution, semantic analysis and lowering belong to later gates.
set -euo pipefail

SOURCE_ROOT=$(cd "${1:-${S_SOURCE_ROOT:-.}}" && pwd)
COMPILER="$SOURCE_ROOT/bin/s_seed"
CLOSURE_FILE="$SOURCE_ROOT/.parser-closure-manifest"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/s-parser-closure.XXXXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

echo 'PARSER CANONICAL CLOSURE CHECK'
echo 'Scope: compiler build sources; lexer -> parser -> AST only'

if [[ ! -x "$COMPILER" ]]; then
    echo "ERROR: seed compiler not executable: $COMPILER" >&2
    exit 1
fi

# Keep the optional explicit manifest, but derive the default from the build
# definition instead of maintaining a second, easily stale source list.
if [[ -f "$CLOSURE_FILE" ]]; then
    cp "$CLOSURE_FILE" "$TEMP_DIR/sources"
elif ! make --no-print-directory -s -C "$SOURCE_ROOT" compiler-source-list > "$TEMP_DIR/sources"; then
    echo 'ERROR: cannot determine compiler build sources' >&2
    exit 1
fi

REQUIRED_FILES=()
while IFS= read -r entry || [[ -n "$entry" ]]; do
    case "$entry" in
        ''|'#'*) continue ;;
    esac
    REQUIRED_FILES+=("$entry")
done < "$TEMP_DIR/sources"

if [[ ${#REQUIRED_FILES[@]} -eq 0 ]]; then
    echo 'RESULT: FAIL (empty compiler source closure)' >&2
    exit 1
fi

parsed=0
errors=0
for srcfile in "${REQUIRED_FILES[@]}"; do
    case "$srcfile" in
        /*) fullpath="$srcfile" ;;
        *) fullpath="$SOURCE_ROOT/$srcfile" ;;
    esac
    if [[ ! -f "$fullpath" ]]; then
        echo "FAIL: $srcfile (required source not found)"
        errors=$((errors + 1))
        continue
    fi

    # AST dumping stops after parsing. Compiling a file alone would instead
    # report semantic errors for types declared in other files of its package.
    if "$COMPILER" --dump-ast "$fullpath" "$TEMP_DIR/source.ast" > "$TEMP_DIR/parser.log" 2>&1; then
        echo "PASS: $srcfile"
        parsed=$((parsed + 1))
    else
        echo "FAIL: $srcfile"
        cat "$TEMP_DIR/parser.log"
        errors=$((errors + 1))
    fi
done

echo "Files required: ${#REQUIRED_FILES[@]}"
echo "Files parsed: $parsed"
echo "Parse errors: $errors"
if [[ $errors -ne 0 ]]; then
    echo 'RESULT: FAIL'
    exit 1
fi
echo 'RESULT: PASS'
