#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-nominal-layout.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/types.s" <<'S'
package shapes
struct Graph { int value }
S
cat > "$work/main.s" <<'S'
package main
import "shapes"
struct Wrapper { Graph graph; Graph[] graphs }
func make_graph(int value) Graph { return Graph { value: value } }
func read(Graph graph) int { return graph.value }
func main() int {
    value := Wrapper { graph: make_graph(40), graphs: [Graph { value: 2 }] }
    empty := Graph[]()
    empty.push(value.graphs[0])
    return read(value.graph) + empty[0].value
}
S
"$compiler" --compile-unit "$work/output.sasm" "$work/main.s" "$work/types.s"
"$compiler" --emit-bin "$work/output.sasm" "$work/output"
status=0; "$work/output" || status=$?
test "$status" -eq 42
echo 'canonical imported nominal record fields, arrays, constructors and signatures: PASS'
