#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-qualified-array.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/types.s" <<'S'
package fixture.types
struct item { int value }
S
cat > "$work/main.s" <<'S'
package main
import "fixture.types"
func validate() () {
    values := fixture.types.item[] {}
    if len(values) != 0 { panic("nonempty initial array") }
    first := fixture.types.item { value: 20 }
    second := fixture.types.item { value: 22 }
    values = append(values, first)
    values = append(values, second)
    if values[0].value + values[1].value != 42 { panic("wrong record elements") }
    filled := fixture.types.item[] { first, second }
    if filled[1].value != 22 { panic("wrong typed literal") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/types.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'qualified typed array literals retain record element types: PASS'
