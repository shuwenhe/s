#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-call-option.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/lib.s" <<'S'
package fixture.lib
import "std.option"
struct record { int value }
func accept(option[record] value) int {
    switch value { option.some(item): item.value, option.none: 20 }
}
S
cat > "$work/main.s" <<'S'
package main
import ("std.option"; "fixture.lib")
func validate() () {
    if fixture.lib.accept(option.none) != 20 { panic("none argument") }
    if fixture.lib.accept(option.some(fixture.lib.record { value: 22 })) != 22 { panic("some argument") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$work/lib.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
sed 's/option.none/option.some("wrong")/' "$work/main.s" > "$work/bad.s"
printf preserve > "$work/bad.ir"
if "$root/bin/s_seed" --compile-native-unit "$work/bad.ir" "$root/src/option/option.s" "$work/lib.s" "$work/bad.s" > "$work/bad.log" 2>&1; then
    echo 'accepted incorrect option payload at call' >&2; exit 1
fi
test "$(cat "$work/bad.ir")" = preserve
echo 'concrete call parameter contexts type none and reject incorrect option payloads: PASS'
