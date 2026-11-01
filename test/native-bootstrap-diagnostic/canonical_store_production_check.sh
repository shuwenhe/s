#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=${S_CANONICAL_STORE_WORK:-"$root/.bootstrap/canonical-production/store"}
mkdir -p "$work"
: > "$work/results.txt"
cat > "$work/main.s" <<'S'
package main
struct Inner { int value }
struct Outer { Inner inner; int tail }
func update(Outer record) Outer { record.inner.value += 1; return record }
func main(int input) int { record := update(Outer { inner: Inner { value: input }, tail: 2 }); values := int[]{0,0}; values[1] = record.inner.value; return values[1] + record.tail }
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
for pair in '39 42' '7 10'; do
 read -r input expected <<< "$pair"
 status=0; "$work/main" "$input" || status=$?
 test "$status" -eq "$expected"
done
cat > "$work/index.s" <<'S'
package main
func index(int value) int { return value % 2 }
func main(int input) int { values := int[]{40,1}; values[index(input)] += 1; return values[0] * 2 + values[1] }
S
"$compiler" "$work/index.s" "$work/index.mir"
test "$(grep -c '^instruction call .*symbol=main.index$' "$work/index.mir")" -eq 1
"$compiler" --compile-unit "$work/index.sasm" "$work/index.s"
"$compiler" --emit-bin "$work/index.sasm" "$work/index"
for pair in '0 83' '1 82'; do
 read -r input expected <<< "$pair"
 status=0; "$work/index" "$input" || status=$?
 test "$status" -eq "$expected"
done
printf preserve > "$work/preserved.sasm"
for mode in field type index; do
 case "$mode" in
  field) sed 's/record.inner.value += 1/record.missing = 42/' "$work/main.s" > "$work/bad.s" ;;
  type) sed 's/record.inner.value += 1/record.inner.value = true/' "$work/main.s" > "$work/bad.s" ;;
  index) sed 's/values\[1\] =/values[false] =/' "$work/main.s" > "$work/bad.s" ;;
 esac
 if "$compiler" --compile-unit "$work/preserved.sasm" "$work/bad.s" > "$work/$mode.log" 2>&1; then
  echo "invalid $mode store accepted" >&2; exit 1
 fi
 grep -q 'canonical semantic:' "$work/$mode.log"
 test "$(cat "$work/preserved.sasm")" = preserve
done
printf 'canonical native nested record and array stores preserve types and evaluate index once: PASS\n'
