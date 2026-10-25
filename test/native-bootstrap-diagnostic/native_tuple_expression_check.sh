#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-tuple-expression.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.s" <<'S'
package main
struct failure { int code }
func compose(string input) (string, failure) { return "prefix:" + input, failure { code: 0 } }
func negate(int value) (int, failure) { return -value, failure { code: 0 } }
func validate() () {
    text, text_error := compose("value")
    number, number_error := negate(42)
    if text != "prefix:value" || text_error.code != 0 { panic("wrong composite return") }
    if number != -42 || number_error.code != 0 { panic("wrong unary return") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/result/result.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
cat > "$work/bad.s" <<'S'
package main
struct failure { int code }
func wrong(string input) (int, failure) { return "prefix:" + input }
func main() int { return 42 }
S
printf preserve > "$work/output"
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/result/result.s" "$work/bad.s" > "$work/bad.log" 2>&1; then
 echo 'accepted mismatched tuple expression' >&2; exit 1
fi
test "$(cat "$work/output")" = preserve
echo 'tuple return expressions preserve binary and unary values natively: PASS'
