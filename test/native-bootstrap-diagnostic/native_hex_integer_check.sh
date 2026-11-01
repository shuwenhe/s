#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-hex.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.s" <<'S'
package main
func validate() () {
    if 0x1000 + 2 != 4098 || 0X2a != 42 { panic("wrong hexadecimal scalar") }
    if 08 != 8 { panic("decimal reinterpreted as octal") }
    if -0x2a != -42 { panic("wrong negative hexadecimal") }
    values := [0x14, 0x16];
    if values[0] + values[1] != 42 { panic("wrong hexadecimal array") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
sed 's/0x1000/0xINVALID/' "$work/main.ir" > "$work/bad.ir"
printf preserve > "$work/output"
if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/bad.ir" "$work/output" > "$work/bad.log" 2>&1; then
 echo 'accepted invalid hexadecimal operand' >&2; exit 1
fi
test "$(cat "$work/output")" = preserve
echo 'native hexadecimal scalars, signed arithmetic, arrays and invalid operand rejection: PASS'
