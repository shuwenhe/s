#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-seed-receiver-lookup.XXXXXX)
trap 'rm -rf "$work"' EXIT
# The bootstrap closure contains abstract result receiver methods as well as
# concrete record receivers. Both must use the same receiver/member key.
"$root/bin/s_seed" --compile-native-unit "$work/result.ir" "$root/src/result/result.s" > "$work/result.log" 2>&1 || { cat "$work/result.log"; exit 1; }
cat "$work/result.log"
test -s "$work/result.ir"
cat > "$work/receiver.s" <<'S'
package main
struct counter { int value }
func (counter* self) number() int { return self.value }
func (counter* self) doubled() int { return self.number() + self.number() }
func main() int {
    value := counter { value: 21 }
    return value.doubled()
}
S
"$root/bin/s_seed" --compile-native-unit "$work/receiver.ir" "$work/receiver.s"
test -s "$work/receiver.ir"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/receiver.ir" "$work/receiver"
status=0
"$work/receiver" || status=$?
test "$status" -eq 42
echo 'seed receiver lookup: PASS'
