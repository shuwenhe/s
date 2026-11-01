#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-global-index-member.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
struct Entry { int value }
counter := 0
entries := [Entry { value: 1 }]
func index() int { counter = counter + 1; return 0 }
func main() int {
    saved := entries[0]
    value := entries[index()].value
    entries[0].value = 39
    return value + saved.value + entries[0].value + counter
}
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'global indexed record reads/stores preserve snapshots and single evaluation: PASS'
