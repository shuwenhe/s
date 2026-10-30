#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-discarded-switch.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
counter := 0
func tick() int { counter = counter + 1; return 7 }
func main(int input) int {
    switch input { 0: tick(), _: () }
    value := 0
    switch input { 0: { value = 39; 99 }, _: { value = 50; () } }
    return value + 2 + counter
}
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
for pair in '0 42' '7 52'; do
    read -r input expected <<< "$pair"
    status=0; "$work/main" "$input" || status=$?
    test "$status" -eq "$expected"
done
cat > "$work/invalid.s" <<'S'
package main
func main(int input) int { value := switch input { 0: 42, _: () }; return value }
S
printf preserve > "$work/rejected.sasm"
if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/invalid.log" 2>&1; then
    echo 'incompatible value-producing switch accepted' >&2; exit 1
fi
grep -q 'canonical semantic:' "$work/invalid.log"
test "$(cat "$work/rejected.sasm")" = preserve
echo 'discarded switch preserves effects and bindings without merging unused arm types: PASS'
cat > "$work/if.s" <<'S'
package main
counter := 0
func tick() int { counter = counter + 1; return 7 }
func main(int input) int {
    value := 0
    if input == 0 { value = 39; tick() }
    return value + 2 + counter
}
S
"$compiler" --compile-unit "$work/if.sasm" "$work/if.s"
"$compiler" --emit-bin "$work/if.sasm" "$work/if"
for pair in '0 42' '7 2'; do
    read -r input expected <<< "$pair"
    status=0; "$work/if" "$input" || status=$?
    test "$status" -eq "$expected"
done
echo 'unit if preserves discarded call effects and binding updates: PASS'
