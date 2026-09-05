#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler="$root/bin/s_nogc_compiler"
if [ ! -x "$compiler" ]; then
    echo 'Build the S ownership compiler first: make nogc-compiler' >&2
    exit 2
fi
if [ "$#" -eq 3 ] && [ "$1" = '--emit-c' ]; then
    exec "$compiler" "$@"
fi
if [ "$#" -eq 2 ] && [ "$1" = 'check' ]; then
    work=$(mktemp -d "${TMPDIR:-/tmp}/s-nogc.XXXXXXXX")
    trap 'rm -rf "$work"' EXIT HUP INT TERM
    "$compiler" --emit-c "$2" "$work/program.c"
    exit 0
fi
if [ "$#" -ne 4 ] || [ "$1" != 'build' ] || [ "$3" != '-o' ]; then
    echo 'usage: s-nogc.sh build input.s -o output | check input.s | --emit-c input.s output.c' >&2
    exit 2
fi
work=$(mktemp -d "${TMPDIR:-/tmp}/s-nogc.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
"$compiler" --emit-c "$2" "$work/program.c"
"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$root/src/runtime" "$work/program.c" -o "$work/program"
# A failed analysis or C compilation never replaces a previous executable.
cp "$work/program" "$4"
chmod +x "$4"
