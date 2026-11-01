#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-array-methods.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
struct Holder { int[] values }
func main() int {
    holder := Holder {}
    holder.values.push(40)
    holder.values.push(0)
    holder.values.set(1, 2)
    if holder.values.len() != 2 { return 1 }
    values := int[]()
    i := 0
    for i < 100 { values.push(i); i = i + 1 }
    if values.len() != 100 || values[99] != 99 { return 2 }
    original := int[]{1}
    original = append(original, 2)
    original = append(original, 3)
    saved := original
    original = append(original, 4)
    if len(saved) != 3 { return 3 }
    return holder.values[0] + holder.values[1]
}
S
"$compiler" --compile-unit "$work/output.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/output.sasm" "$work/output"
status=0; "$work/output" || status=$?
test "$status" -eq 42
echo 'canonical nested and default array push/set/len and capacity growth: PASS'
