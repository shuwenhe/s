#!/bin/sh
set -eu

dir=${1:?usage: write-manifest.sh DIR OUTPUT [RUNTIME]}
output=${2:?usage: write-manifest.sh DIR OUTPUT [RUNTIME]}
runtime=${3:-}
tmp="${output}.tmp.$$"
trap 'rm -f "$tmp"' EXIT HUP INT TERM

{
    printf 's-bootstrap-manifest-v1\n'
    for name in stage1.ir stage2.ir stage3.ir stage2.S stage3.S stage1 stage2 stage3; do
        path="$dir/$name"
        if [ -f "$path" ]; then
            digest=$(sha256sum "$path" | awk '{print $1}')
            printf '%s  %s\n' "$digest" "$name"
        fi
    done
    if [ -n "$runtime" ] && [ -f "$runtime" ]; then
        digest=$(sha256sum "$runtime" | awk '{print $1}')
        printf '%s  %s\n' "$digest" runtime
    fi
} >"$tmp"
mv "$tmp" "$output"
trap - EXIT HUP INT TERM
