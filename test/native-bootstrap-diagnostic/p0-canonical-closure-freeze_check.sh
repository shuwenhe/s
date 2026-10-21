#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-p0-closure.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

mkdir -p "$work/repo/.bootstrap/modular" "$work/repo/src"
printf '%s\n' 'src/a.s' 'src/a.s' >"$work/repo/.bootstrap/modular/canonical-closure.txt"
printf '%s\n' 'package a' >"$work/repo/src/a.s"

if "$root/misc/scripts/p0-canonical-closure-freeze.sh" "$work/repo" >"$work/out" 2>&1; then
    echo 'expected duplicate closure to fail' >&2
    exit 1
fi
grep -q 'duplicate' "$work/out"

echo 'P0 canonical closure freeze RED: duplicate closure rejected'
