#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-generic-enum.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "enum artifacts: $work" >&2; fi' EXIT
cat > "$work/enum.s" <<'S'
package main
enum choice[t,e] { good(t), bad(e) }
func good(int value) choice[int,string] { return choice.good(value) }
func bad(string message) choice[int,string] { return choice.bad(message) }
func (choice[t,e]* self) get(t fallback) t {
    switch self { choice::good(value): value, choice::bad(_): fallback }
}
func (choice[t,e]* self) error(e fallback) e {
    switch self { choice::good(_): fallback, choice::bad(message): message }
}
func main() int {
    one := good(40)
    two := bad("ok")
    return one.get(0) + len(two.error(""))
}
S
"$root/bin/s_seed" --compile-native-unit "$work/enum.ir" "$work/enum.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/enum.ir" "$work/enum"
status=0; timeout 15 "$work/enum" || status=$?
test "$status" -eq 42
echo 'native concrete enum payload selection and borrowed generic methods: PASS'
cat > "$work/tuple.s" <<'S'
package main
import "std.result"
struct failure { string message }
struct answer { int value }
func good() (answer, failure) { return result.ok(answer { value: 40 }) }
func bad() (answer, failure) { return result.err(failure { message: "ok" }) }
func main() int {
    pair := good()
    if pair.left.value != 40 { return 1 }
    if pair.right.message != "" { return 2 }
    first, no_error := good()
    empty, error := bad()
    return first.value + len(error.message) + empty.value + len(no_error.message)
}
S
"$root/bin/s_seed" --compile-native-unit "$work/tuple.ir" "$root/src/result/result.s" "$work/tuple.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/tuple.ir" "$work/tuple"
status=0; timeout 15 "$work/tuple" || status=$?
test "$status" -eq 42
echo 'native result destructuring projects both typed payloads: PASS'
