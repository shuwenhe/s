#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=${S_CANONICAL_ARRAY_WORK:-"$root/.bootstrap/canonical-production/array"}
mkdir -p "$work"
: > "$work/results.txt"
cat > "$work/main.s" <<'S'
package main
func build(int value) int[] { return int[]{value, 2} }
func main(int value) int { values := build(value); values = append(values, 3); return values[0] + values[1] + len(values) }
S
"$compiler" "$work/main.s" "$work/main.mir"
grep -q '^instruction array_new ' "$work/main.mir"
grep -q '^instruction array_get ' "$work/main.mir"
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
for pair in '37 42' '7 12'; do
 read -r input expected <<< "$pair"
 status=0; "$work/main" "$input" || status=$?
 test "$status" -eq "$expected"
 printf '%s -> %s\n' "$input" "$status" >> "$work/results.txt"
done
cat > "$work/bounds.s" <<'S'
package main
func main(int index) int { values := int[]{40,2}; return values[index] }
S
"$compiler" --compile-unit "$work/bounds.sasm" "$work/bounds.s"
"$compiler" --emit-bin "$work/bounds.sasm" "$work/bounds"
for index in -1 2; do
 status=0; "$work/bounds" "$index" || status=$?
 test "$status" -eq 87
done
printf preserve > "$work/preserved.sasm"
for mode in literal append index; do
 case "$mode" in
  literal) sed 's/int\[\]{value, 2}/int[]{true}/' "$work/main.s" > "$work/$mode.s" ;;
  append) sed 's/append(values, 3)/append(values, true)/' "$work/main.s" > "$work/$mode.s" ;;
  index) sed 's/values\[0\]/values[false]/' "$work/main.s" > "$work/$mode.s" ;;
 esac
 if "$compiler" --compile-unit "$work/preserved.sasm" "$work/$mode.s" > "$work/$mode.log" 2>&1; then
  echo "canonical production accepted $mode array program" >&2; exit 1
 fi
 grep -q 'canonical semantic:' "$work/$mode.log"
 test "$(cat "$work/preserved.sasm")" = preserve
done
printf 'canonical Parser/Semantic/MIR/SSA/native array execution and bounds: PASS\n'
