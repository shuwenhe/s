#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-tuple-result-methods.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
struct Error { string message }
counter := 0
func pair() (int,string) { counter = counter + 1; return 42, "payload" }
func marked() (int,Error) { return 7, Error { message: "preserved" } }
func main(int input) int {
    value := pair()
    if value.is_err() || !value.is_ok() { return 1 }
    first, second := value
    if first != 42 || second != "payload" { return 2 }
    if !pair().is_ok() || counter != 2 { return 3 }
    record := marked()
    if record.is_err() { return 4 }
    ignored, error := record
    if error.message != "preserved" { return 5 }
    if input == 1 { unused := value.unwrap_err(); return 6 }
    if input == 2 { unused := record.unwrap_err(); return 7 }
    return value.unwrap()
}
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" 0 || status=$?
test "$status" -eq 42
for input in 1 2; do
    status=0; "$work/main" "$input" > "$work/panic-$input.log" 2>&1 || status=$?
    test "$status" -eq 101
done
sed 's/value.unwrap()/value.unwrap(1)/' "$work/main.s" > "$work/invalid.s"
printf preserve > "$work/rejected.sasm"
if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/invalid.log" 2>&1; then
    echo 'result method accepted arguments' >&2; exit 1
fi
grep -q 'canonical semantic:' "$work/invalid.log"
test "$(cat "$work/rejected.sasm")" = preserve
echo 'tuple result status, payload preservation, single evaluation and checked unwrap: PASS'
