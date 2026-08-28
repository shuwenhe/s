#!/usr/bin/env sh
set -eu

if [ $# -lt 2 ]; then
    printf '%s\n' "usage: source_closure.sh <root-source> <output-file>" >&2
    exit 1
fi

root_source=$1
output_file=$2

root_dir=$(dirname "$root_source")

{
    printf '%s\n' "$root_source"
    find "$root_dir" -name '*.s' | sort
} > "$output_file"

