#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-tuple-tail.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
for mode in call literal explicit; do
 case "$mode" in
  call) body='source(value)' ;;
  literal) body='(value, "ok")' ;;
  explicit) body='return source(value)' ;;
 esac
 cat > "$work/$mode.s" <<S
package main
func source(int value) (int,string) { return value, "ok" }
func relay(int value) (int,string) { $body }
func main(int input) int { a, b := relay(input); if b != "ok" { return 1 }; return a + 41 }
S
 "$compiler" --compile-unit "$work/$mode.sasm" "$work/$mode.s"
 "$compiler" --emit-bin "$work/$mode.sasm" "$work/$mode"
 sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/$mode"
 for pair in '1 42' '7 48'; do
  read -r input expected <<< "$pair"
  status=0; "$work/$mode" "$input" || status=$?
  test "$status" -eq "$expected"
 done
done
printf keep > "$work/rejected.sasm"
for mode in element arity scalar; do
 case "$mode" in
  element) wanted='(int,bool)' ;;
  arity) wanted='(int,string,int)' ;;
  scalar) wanted='int' ;;
 esac
 cat > "$work/rejected.s" <<S
package main
func source() (int,string) { return 1, "ok" }
func wrong() $wanted { source() }
func main() int { return 42 }
S
 if "$compiler" --compile-unit "$work/rejected.sasm" "$work/rejected.s" > "$work/$mode.log" 2>&1; then echo "accepted invalid tuple tail $mode" >&2; exit 1; fi
 rg -q 'e3004' "$work/$mode.log"
 rg -q 'tail_expr_kind=call' "$work/$mode.log"
 test "$(cat "$work/rejected.sasm")" = keep
done
echo 'native tuple literal/call/explicit returns, dynamic values and strict element/arity rejection: PASS'
