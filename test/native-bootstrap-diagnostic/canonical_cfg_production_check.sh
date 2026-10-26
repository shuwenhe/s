#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=${S_CANONICAL_CFG_WORK:-"$root/.bootstrap/canonical-production/cfg"}
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
cat > "$work/branch.s" <<'S'
package main
func main(int value) int { answer := 0; if value > 2 { answer = 40 } else { answer = 20 }; return answer + 2 }
S
compile_run branch '7 42' '2 22' '-3 22'
cat > "$work/early.s" <<'S'
package main
func main(int value) int { if value < 0 { return 7 }; if value == 0 { return 9 } else { return 42 } }
S
compile_run early '-3 7' '0 9' '7 42'
cat > "$work/loop.s" <<'S'
package main
func main(int value) int { total := 0; index := 0; while index < value { total = total + index; index = index + 1 }; return total }
S
compile_run loop '0 0' '7 21' '-3 0'
cat > "$work/swap.s" <<'S'
package main
func main(int value) int { first := 1; second := 2; index := 0; for index < value { temp := first; first = second; second = temp; index = index + 1 }; return first * 10 + second }
S
compile_run swap '0 12' '1 21' '2 12' '7 21'
cat > "$work/short.s" <<'S'
package main
func main(int value) int { if value != 0 && 10 / value > 1 { return 42 }; if value == 0 || 10 / value < 0 { return 7 }; return 9 }
S
compile_run short '0 7' '2 42' '10 9' '-2 7'
printf 'canonical native branches, loop phi values, parallel phi copies and short-circuit evaluation: PASS\n'
cat > "$work/condition.s" <<'S'
package main
func main(int input) int { value := 0; while (if value < input { value = value + 1; true } else { false }) {}; return value }
S
compile_run condition '0 0' '1 1' '7 7'
cat > "$work/scope.s" <<'S'
package main
func main(int input) int { value := { temporary := 40; temporary }; temporary := 2; return value + temporary }
S
compile_run scope '0 42'
cat > "$work/nested_store.s" <<'S'
package main
func main(int input) int { values := int[]{10}; other := int[]{20}; values[{ other[0] = 1; 0 }] = 42; return values[0] + other[0] }
S
compile_run nested_store '0 43'
