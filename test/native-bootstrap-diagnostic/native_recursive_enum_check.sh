#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-recursive-enum.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "enum artifacts: $work" >&2; fi' EXIT
cat > "$work/input.s" <<'S'
package main
struct box[t] { t value }
func wrap[t](t value) box[t] { return box[t] { value: value } }
enum node { number(int), pair(pair_node), empty }
struct pair_node { box[node] left, box[node] right }
func sum(node input) int {
    switch input {
        node.number(value): value,
        node.empty: 0,
        node.pair(value): sum(value.left.value) + sum(value.right.value),
    }
}
func main() int {
    left := node.number(20)
    right := node.number(22)
    tree := node.pair(pair_node { left: wrap(left), right: wrap(right) })
    left = node.number(1)
    if sum(node.empty) != 0 { return 1 }
    return sum(tree)
}
S
"$root/bin/s_seed" --compile-native-unit "$work/tree.ir" "$work/input.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/tree.ir" "$work/tree"
status=0; timeout 15 "$work/tree" || status=$?; test "$status" -eq 42
echo 'recursive nongeneric enum payloads execute through typed variants: PASS'
