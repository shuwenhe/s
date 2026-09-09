#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
driver="$root/misc/scripts/s-driver.sh"
if [ "$#" -eq 2 ] && [ "$1" = 'check' ]; then
    work=$(mktemp -d "${TMPDIR:-/tmp}/s-compiler.XXXXXXXX")
    trap 'rm -rf "$work"' EXIT HUP INT TERM
    "$driver" --emit-c "$2" "$work/program.c"
    exit 0
fi
exec "$driver" "$@"
