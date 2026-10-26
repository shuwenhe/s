#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-temporary-effects.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/parameter.s" <<'S'
package main
func change(string[] values) int {
    values.set(0, "hello" + "world")
    i := 0
    while i < 5000 { dead := "trash" + "trash"; i = i + 1 }
    if values[0] == "helloworld" { return 42 }
    return 9
}
func main() int { return change(["before"]) }
S
cat > "$work/global.s" <<'S'
package main
values := string[]()
func add() () { values.push("hello" + "world") }
func relay() () { add() }
func main() int {
    relay()
    i := 0
    while i < 5000 { dead := "trash" + "trash"; i = i + 1 }
    if values[0] == "helloworld" { return 42 }
    return 9
}
S
cat > "$work/deep.s" <<'S'
package main
func main() int {
    text := ""
    i := 0
    while i < 1000000 { text = text + "x"; i = i + 1 }
    if len(text) == 1000000 { return 42 }
    return 9
}
S
for name in parameter global deep; do
    "$root/bin/s_seed" --compile-native-unit "$work/$name.ir" "$work/$name.s"
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$name.ir" "$work/$name"
    python3 - "$work/$name" <<'PY'
import resource, subprocess, sys
def limits():
    resource.setrlimit(resource.RLIMIT_AS, (128 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (15, 15))
    resource.setrlimit(resource.RLIMIT_STACK, (8 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
result = subprocess.run([sys.argv[1]], preexec_fn=limits, timeout=20)
assert result.returncode == 42, f'{sys.argv[1]}: expected 42, got {result.returncode}'
PY
    echo "$name lifetime/stack regression: PASS"
done
