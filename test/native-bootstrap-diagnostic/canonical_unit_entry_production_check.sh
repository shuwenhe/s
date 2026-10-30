#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-unit-entry.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/helper.s" <<'S'
package helper
func twice(int value) int { return value * 2 }
S
cat > "$work/main.s" <<'S'
package app
import "helper"
func main(int input) int { return helper.twice(input) + 40 }
S
for order in entry-first dependency-first; do
    sources=("$work/main.s" "$work/helper.s")
    if [ "$order" = dependency-first ]; then sources=("$work/helper.s" "$work/main.s"); fi
    "$compiler" --compile-unit "$work/$order.sasm" "${sources[@]}"
    "$compiler" --emit-bin "$work/$order.sasm" "$work/$order"
    for input in 1 7; do
        status=0; "$work/$order" "$input" || status=$?
        test "$status" -eq "$((input * 2 + 40))"
    done
done
cat > "$work/other.s" <<'S'
package other
func main() int { return 0 }
S
printf preserve > "$work/preserved.sasm"
if "$compiler" --compile-unit "$work/preserved.sasm" "$work/main.s" "$work/helper.s" "$work/other.s" > "$work/error.log" 2>&1; then
    echo 'ambiguous entry accepted' >&2; exit 1
fi
grep -q 'ambiguous entry' "$work/error.log"
test "$(cat "$work/preserved.sasm")" = preserve
echo 'compile-unit entry follows its unique main across package/source order and rejects ambiguity: PASS'
