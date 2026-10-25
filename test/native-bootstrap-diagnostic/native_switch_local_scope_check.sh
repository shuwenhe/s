#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-switch-scope.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "switch scope artifacts: $work" >&2; fi' EXIT
cat > "$work/main.s" <<'S'
package main
enum number { value(int), empty }
func read(number input, number[] values) int {
    return switch input {
        number.value(_): {
            index := 0
            switch values[index] {
                number.value(n): n,
                number.empty: 0,
            }
        }
        number.empty: 0,
    }
}
func main() int {
    n := number.value(42)
    return read(n, [n])
}
S
"$root/bin/s_seed" --compile-native-unit "$work/test.ir" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/test.ir" "$work/test"
status=0; "$work/test" || status=$?; test "$status" -eq 42
echo 'nested switch expression resolves arm-local index: PASS'
