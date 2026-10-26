#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=${S_CANONICAL_BOOL_WORK:-"$root/.bootstrap/canonical-production/bool"}
mkdir -p "$work"
: > "$work/results.txt"
cat > "$work/main.s" <<'S'
package main
func same(int left, int right) bool { return left == right }
func identity(bool value) bool { return value }
func main(int value) int { return 41 + int(identity(!same(value, 2))) }
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
for pair in '2 41' '7 42'; do
 read -r input expected <<< "$pair"
 status=0; "$work/main" "$input" || status=$?
 test "$status" -eq "$expected"
done
for op in '<' '<=' '>' '>=' '==' '!='; do
 printf 'package main\nfunc main(int value) int { return 41 + int(value %s 2) }\n' "$op" > "$work/compare.s"
 "$compiler" --compile-unit "$work/compare.sasm" "$work/compare.s"
 "$compiler" --emit-bin "$work/compare.sasm" "$work/compare"
 for input in -3 2 7; do
  expected=$(python3 - "$op" "$input" <<'PY_COMPARE'
import sys
op,x=sys.argv[1],int(sys.argv[2])
print(41 + int({'<':x<2,'<=':x<=2,'>':x>2,'>=':x>=2,'==':x==2,'!=':x!=2}[op]))
PY_COMPARE
)
  status=0; "$work/compare" "$input" || status=$?
  test "$status" -eq "$expected"
 done
done
printf 'canonical native bool constants, calls, negation and signed comparisons: PASS\n'
