#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-temporary-values.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/values.s" <<'S'
package main
struct leaf { string text; int number }
struct tree { leaf[] leaves; string label }
func build(int number) tree {
    dead := "temporary" + "discarded"
    child := leaf { text: "value" + " retained", number: number }
    return tree { leaves: [child], label: "outer" + " rope" }
}
func consume(tree original) int {
    value := original
    i := 0
    while i < 3000 {
        next := build(42)
        value = next
        i = i + 1
    }
    copy := value
    copy.leaves[0].number = 7
    if value.leaves[0].number != 42 { return 1 }
    if len(value.leaves[0].text) != 14 { return 2 }
    if len(value.label) != 10 { return 3 }
    if original.leaves[0].number != 9 { return 4 }
    return value.leaves[0].number
}
func main() int { return consume(build(9)) }
S
"$root/bin/s_seed" --compile-native-unit "$work/values.ir" "$work/values.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/values.ir" "$work/values"
python3 - "$work/values" <<'PY'
import resource, subprocess, sys
def limits():
    resource.setrlimit(resource.RLIMIT_AS, (64 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (15, 15))
result = subprocess.run([sys.argv[1]], preexec_fn=limits, timeout=20)
assert result.returncode == 42, f'temporary graph lifetime/copy regression: {result.returncode}'
print('nested records/arrays/ropes survive return and loop reclamation under 64 MiB: PASS')
PY
