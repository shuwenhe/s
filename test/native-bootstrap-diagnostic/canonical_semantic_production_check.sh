#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-semantic.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
for body in 'return value + 1' 'value + 1'; do
 printf 'package main\nfunc main(int value) int { %s }\n' "$body" > "$work/main.s"
 "$compiler" "$work/main.s" "$work/main.mir"
done
for body in '' 'return true' 'return unknown'; do
 printf 'package main\nfunc main(int value) int { %s }\n' "$body" > "$work/main.s"
 printf preserve > "$work/main.mir"
 if "$compiler" "$work/main.s" "$work/main.mir" > "$work/error.log" 2>&1; then echo 'invalid function accepted' >&2; exit 1; fi
 grep -q 'canonical semantic:' "$work/error.log"
 test "$(cat "$work/main.mir")" = preserve
done
echo 'canonical semantic preserves valid returns and rejects fallthrough/type/name errors: PASS'
