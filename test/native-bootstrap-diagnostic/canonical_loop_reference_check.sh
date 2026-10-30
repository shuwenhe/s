#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-loop-reference.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
struct Counter { int value }
func bump(Counter* value) { value.value = value.value + 1 }
func advance(Counter* value) {
    i := 0
    for i < 4 {
        i = i + 1
        if i == 2 { continue }
        bump(value)
        if value.value == 42 { break }
    }
}
func nested(Counter* value) {
    i := 0
    for i < 2 {
        j := 0
        for j < 2 { bump(value); j = j + 1 }
        i = i + 1
    }
}
func read(&Counter value) int {
    total := 0
    i := 0
    for i < 2 { total = total + value.value; i = i + 1 }
    return total / 2
}
func main(int input) int {
    value := Counter { value: 40 }
    if input == 1 { value.value = 38; nested(value*) } else { advance(value*) }
    return read(&value)
}
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
for input in 0 1; do
    status=0; timeout 15 "$work/main" "$input" || status=$?
    test "$status" -eq 42 || { echo "loop reference mutation failed: exit=$status" >&2; exit 1; }
done
for body in 'a = b; i = i + 1' 'a = b; break'; do
    cat > "$work/invalid.s" <<S
package main
struct Counter { int value }
func rewire(Counter* a, Counter* b) { i := 0; for i < 1 { $body } }
func main() int { first := Counter { value: 1 }; second := Counter { value: 2 }; rewire(first*, second*); return first.value }
S
    printf preserve > "$work/rejected.sasm"
    if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/rejected.log" 2>&1; then
        echo 'reference identity change across loop accepted' >&2; exit 1
    fi
    grep -q 'loop changes borrowed reference identity' "$work/rejected.log"
    test "$(cat "$work/rejected.sasm")" = preserve
done
echo 'canonical invariant loop references preserve mutation, nested loops, continue/break and reject rewiring: PASS'
