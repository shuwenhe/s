#!/bin/sh
# DEPRECATED: This script is no longer used.
#
# This was part of the old manifest-based bootstrap approach.
# The S compiler now uses import-driven bootstrap (similar to Go).
# See: docs/BOOTSTRAP_MODERNIZATION.md
#
# The manifest file (selfhost-sources.txt) has been removed.
# All imports are now declared in src/cmd/compile/main.s and aggregate packages.
#
# This script is kept for historical reference only.

set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
output=${1:?usage: materialize-selfhost-source.sh OUTPUT}
manifest=${S_BOOTSTRAP_SOURCE_MANIFEST:-"$root/src/cmd/compile/selfhost-sources.txt"}

[ -f "$manifest" ] || {
    printf '%s\n' "selfhost source manifest not found: $manifest" >&2
    printf '%s\n' "(NOTE: This script is deprecated. Use native-bootstrap-imports instead.)" >&2
    exit 1
}

mkdir -p "$(dirname "$output")"
: >"$output"
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in
        \#*) continue ;;
    esac
    case "$rel" in
        extract:selfhost-main:*)
            source_rel=${rel#extract:selfhost-main:}
            path="$root/$source_rel"
            [ -f "$path" ] || {
                printf '%s\n' "selfhost source fragment not found: $source_rel" >&2
                exit 1
            }
            awk '
                /^[[:space:]]*\/\/ SELFHOST_MAIN_BEGIN/ { in_block = 1; next }
                /^[[:space:]]*\/\/ SELFHOST_MAIN_END/ { in_block = 0; next }
                in_block && /^[[:space:]]*\/\/ SELFHOST_MAIN_LINE/ {
                    line = $0
                    sub(/^[[:space:]]*\/\/ SELFHOST_MAIN_LINE ?/, "", line)
                    sub(/^func selfhost_main[(][)]/, "func main()", line)
                    print line
                }
            ' "$path" >>"$output"
            continue
            ;;
    esac
    path="$root/$rel"
    [ -f "$path" ] || {
        printf '%s\n' "selfhost source fragment not found: $rel" >&2
        exit 1
    }
    cat "$path" >>"$output"
done <"$manifest"
