#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-generic-caller-borrow.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/library.s" <<'S'
package factory
import "std.result"
func answer() result[int,string] { return result.ok(42) }
S
cat > "$work/caller.s" <<'S'
package main
import "std.result"
import "factory"
func main() int {
    value := factory.answer()
    if value.is_err() { return 1 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/caller.ir" "$root/src/result/result.s" "$work/library.s" "$work/caller.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/caller.ir" "$work/caller"
status=0; timeout 15 "$work/caller" || status=$?
test "$status" -eq 42
# unwrap's return type must also survive receiver borrowing and type checking.
sed 's/return 42/return value.unwrap()/' "$work/caller.s" > "$work/unwrap.s"
"$root/bin/s_seed" --compile-native-unit "$work/unwrap.ir" "$root/src/result/result.s" "$work/library.s" "$work/unwrap.s"
echo 'native generic receiver borrowing from an owned caller: PASS'
