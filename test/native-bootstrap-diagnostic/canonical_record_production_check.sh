#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=${S_CANONICAL_RECORD_WORK:-"$root/.bootstrap/canonical-production/record"}
mkdir -p "$work"
: > "$work/results.txt"
cat > "$work/main.s" <<'S'
package main
struct Pair { int first; int second }
func build(int value) Pair { return Pair { second: 2, first: value } }
func sum(Pair pair) int { return pair.first + pair.second }
func main(int value) int { return sum(build(value)) }
S
"$compiler" "$work/main.s" "$work/main.mir"
grep -q '^instruction record_new .*types=main.Pair ' "$work/main.mir"
grep -q '^instruction record_get ' "$work/main.mir"
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
for pair in '40 42' '7 9'; do
 read -r input expected <<< "$pair"
 status=0; "$work/main" "$input" || status=$?
 test "$status" -eq "$expected"
 printf '%s -> %s\n' "$input" "$status" >> "$work/results.txt"
done
sed 's/second: 2, //' "$work/main.s" > "$work/default.s"
"$compiler" --compile-unit "$work/default.sasm" "$work/default.s"
"$compiler" --emit-bin "$work/default.sasm" "$work/default"
status=0; "$work/default" 42 || status=$?
test "$status" -eq 42
printf preserve > "$work/preserved.sasm"
for mode in missing duplicate wrongtype; do
 case "$mode" in
  missing) sed 's/first: value/missing: value/' "$work/main.s" > "$work/$mode.s" ;;
  duplicate) sed 's/second: 2/first: 2/' "$work/main.s" > "$work/$mode.s" ;;
  wrongtype) sed 's/first: value/first: true/' "$work/main.s" > "$work/$mode.s" ;;
 esac
 if "$compiler" --compile-unit "$work/preserved.sasm" "$work/$mode.s" > "$work/$mode.log" 2>&1; then
  echo "canonical production accepted $mode record program" >&2; exit 1
 fi
 grep -q 'canonical semantic:' "$work/$mode.log"
 test "$(cat "$work/preserved.sasm")" = preserve
done
printf 'canonical Parser/Semantic/MIR/SSA/native record execution: PASS\n'
