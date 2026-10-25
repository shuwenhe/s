#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-explicit-option.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.s" <<'S'
package main
import ("std.option"; "std.prelude")
struct payload { int amount }
struct holder { option[string] text }
func validate() () {
    text := option[string].none
    if text.is_some() { panic("none became some") }
    text = option[string].some("correct")
    if text.unwrap() != "correct" { panic("wrong explicit string payload") }
    box := option[std.prelude.box[payload]].none
    if box.is_some() { panic("nested none became some") }
    item := payload { amount: 42 }
    box = option[std.prelude.box[payload]].some(std.prelude.box(item))
    if box.unwrap().value.amount != 42 { panic("wrong nested generic payload") }
    values := option[int[]].none
    if values.is_some() { panic("array none became some") }
    values = option[int[]].some([20, 22])
    if values.unwrap()[0] + values.unwrap()[1] != 42 { panic("wrong array type argument") }
    field := holder { text: option[string].none }
    if field.text.is_some() { panic("wrong explicit field type") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$root/src/prelude/prelude.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
cat > "$work/bad.s" <<'S'
package main
import "std.option"
func main() int { value := option[int].some("wrong"); return 42 }
S
printf preserve > "$work/output"
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/option/option.s" "$work/bad.s" > "$work/bad.log" 2>&1; then
 echo 'accepted explicit generic argument with incompatible payload' >&2; exit 1
fi
test "$(cat "$work/output")" = preserve
cat > "$work/context.s" <<'S'
package main
import "std.option"
struct holder { option[string] text }
func main() int { value := holder { text: option[int].none }; return 42 }
S
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/option/option.s" "$work/context.s" > "$work/context.log" 2>&1; then
 echo 'accepted explicit generic argument incompatible with field context' >&2; exit 1
fi
test "$(cat "$work/output")" = preserve
echo 'explicit option constructors preserve concrete and nested type arguments and reject mismatches: PASS'
