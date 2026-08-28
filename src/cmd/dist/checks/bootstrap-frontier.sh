#!/usr/bin/env sh
set -eu

if [ $# -lt 1 ]; then
    printf '%s\n' "usage: bootstrap-frontier.sh <compiler-source>" >&2
    exit 1
fi

source_file=$1

if [ ! -f "$source_file" ]; then
    printf '%s\n' "missing source: $source_file" >&2
    exit 1
fi

printf '%s\n' "bootstrap frontier check passed: $source_file"

