#!/bin/sh
set -eu

entry=${1:?usage: source_closure.sh ENTRY OUTPUT}
output=${2:?usage: source_closure.sh ENTRY OUTPUT}
root=${S_SOURCE_ROOT:-$(pwd)}
resolver="$root/misc/tools/s_resolver"
tmp="${output}.tmp.$$"
trap 'rm -f "$tmp"' EXIT HUP INT TERM

if [ -x "$resolver" ]; then
    "$resolver" "$root" "$entry" | sed "s#^$root/##" | LC_ALL=C sort -u >"$tmp"
    mv "$tmp" "$output"
    trap - EXIT HUP INT TERM
    exit 0
fi

{
    printf '%s\n' "$entry"
    sed -n 's/^[[:space:]]*use[[:space:]]\([^[:space:]]*\).*/\1/p' "$entry" |
    while IFS= read -r module; do
        path=$(printf '%s' "$module" | tr . /)
        if [ -f "$root/src/$path.s" ]; then
            printf 'src/%s.s\n' "$path"
        elif [ -f "$root/src/$path/$path.s" ]; then
            printf 'src/%s/%s.s\n' "$path" "$path"
        fi
    done
} | LC_ALL=C sort -u >"$tmp"
mv "$tmp" "$output"
trap - EXIT HUP INT TERM
