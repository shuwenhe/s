#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=${S_CANONICAL_ENUM_WORK:-"$root/.bootstrap/canonical-production/enum"}
mkdir -p "$work"
: > "$work/results.txt"
cat > "$work/main.s" <<'S'
package main
enum Code { zero, answer = 40, next, }
func main(int value) int { return int(Code.answer) + value }
S
"$compiler" "$work/main.s" "$work/main.mir"
grep -Fxq 'enum main.Code answer=40' "$work/main.mir"
grep -q '^instruction const_enum .*types=main.Code .*integer=40 .*symbol=main.Code.answer$' "$work/main.mir"
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
for pair in '2 42' '7 47'; do
 read -r input expected <<< "$pair"
 status=0; "$work/main" "$input" || status=$?
 test "$status" -eq "$expected"
 printf '%s -> %s\n' "$input" "$status" >> "$work/results.txt"
done
sed 's/answer = 40/answer = 41/' "$work/main.s" > "$work/changed.s"
"$compiler" --compile-unit "$work/changed.sasm" "$work/changed.s"
"$compiler" --emit-bin "$work/changed.sasm" "$work/changed"
status=0; "$work/changed" 2 || status=$?
test "$status" -eq 43
printf 'changed tag: 2 -> %s\n' "$status" >> "$work/results.txt"
printf preserve > "$work/preserved.sasm"
for mode in missing duplicate wrongtype; do
 case "$mode" in
  missing) sed 's/Code.answer/Code.missing/' "$work/main.s" > "$work/$mode.s" ;;
  duplicate) sed 's/zero, answer/answer, answer/' "$work/main.s" > "$work/$mode.s" ;;
  wrongtype) sed 's/int(Code.answer)/Code.answer/' "$work/main.s" > "$work/$mode.s" ;;
 esac
 if "$compiler" --compile-unit "$work/preserved.sasm" "$work/$mode.s" > "$work/$mode.log" 2>&1; then
  echo "canonical production accepted $mode enum program" >&2; exit 1
 fi
 grep -q "canonical semantic:" "$work/$mode.log"
 test "$(cat "$work/preserved.sasm")" = preserve
done
printf 'canonical Parser/Semantic/MIR/SSA/native enum execution: PASS\n'
