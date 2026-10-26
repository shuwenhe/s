#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=${S_CANONICAL_CFG_WORK:-"$root/.bootstrap/canonical-production/tuple"}
mkdir -p "$work"
: > "$work/results.txt"
compile_run() {
 local name=$1; shift
 "$compiler" --compile-unit "$work/$name.sasm" "$work/$name.s"
 "$compiler" --emit-bin "$work/$name.sasm" "$work/$name"
 sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/$name"
 for pair in "$@"; do
  read -r input expected <<< "$pair"
  status=0; timeout 5 "$work/$name" "$input" || status=$?
  test "$status" -eq "$expected"
 done
}
cat > "$work/tuple.s" <<'S'
package main
struct point { int x; int y }
func pair(int input) (int,int) { return input, input + 2 }
func nested(int input) ((int,int),point) { return pair(input), point { x: 2, y: 3 } }
func main(int input) int {
    first, second := pair(input)
    first, second = second, first
    left, right := nested(first)
    a, b := left
    _, ignored := pair(0)
    return a + b + right.x + right.y + ignored + second
}
S
compile_run tuple '1 16' '7 34' '0 13'
cat > "$work/mismatch.s" <<'S'
package main
func main(int input) int { first, second := 1, true; first, second = second, first; return first }
S
if "$compiler" --compile-unit "$work/mismatch.sasm" "$work/mismatch.s"; then echo 'invalid parallel assignment accepted' >&2; exit 1; fi
echo 'canonical native tuples, nested aggregate returns and parallel assignment: PASS'
