#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-switch-default.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/default.s" <<'S'
package main
struct state { int value }
func bump(target* state) { target.value = target.value + 1 }
func dispatch(target* state, string key) {
    switch key {
    case "present": target.value = 1
    default:
        if key == "missing" { target.value = 41 } else { bump(target) }
    }
}
func choose(target* state, string key) int {
    switch key {
    case "present": 2
    default: 40
    }
}
func main() int {
    value := state {}
    dispatch(value, "missing")
    return choose(value, "missing") + choose(value, "present") + value.value - 41
}
S
"$root/bin/s_seed" --compile-native-unit "$work/default.ir" "$work/default.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/default.ir" "$work/default"
status=0; "$work/default" || status=$?
test "$status" -eq 42
echo 'native switch default and selected case: PASS'
