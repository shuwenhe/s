#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-layout-identity.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import "library.types"
func read(Item value) int { return value.value }
func main() int {
    items := Item[]()
    items.push(Item { value: 42 })
    return read(items[0])
}
package library.types
struct Item { int value }
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
cat > "$work/scalar.s" <<'S'
package main
func read(int* value) int { return 42 }
func main() int { value := 42; return read(value*) }
S
"$compiler" --compile-unit "$work/scalar.sasm" "$work/scalar.s"
"$compiler" --emit-bin "$work/scalar.sasm" "$work/scalar"
status=0; "$work/scalar" || status=$?
test "$status" -eq 42
for type in Unknown 'Unknown[]' 'Unknown[int]'; do
    printf 'package main\nfunc invalid(%s* value) () {}\nfunc main() int { return 42 }\n' "$type" > "$work/invalid.s"
    if "$compiler" --compile-unit "$work/invalid.sasm" "$work/invalid.s" > "$work/rejected.log" 2>&1; then
        echo "undefined referent accepted: $type" >&2; exit 1
    fi
done
echo 'canonical layout identities resolve imported names and reject unknown references: PASS'
