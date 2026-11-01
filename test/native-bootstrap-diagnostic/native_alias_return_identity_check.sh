#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-alias-return-identity.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/library.s" <<'S'
package library
import "std.option"
struct item { int value }
func make_item() option[item] { return option.some(item { value: 42 }) }
S
cat > "$work/main.s" <<'S'
package main
use library as lib
struct item { string value }
func main() int {
    found := lib.make_item()
    if found.is_some() { return 42 }
    return 1
}
S
for order in first second; do
    sources=("$work/library.s" "$work/main.s")
    if [ "$order" = second ]; then sources=("$work/main.s" "$work/library.s"); fi
    "$root/bin/s_seed" --compile-native-unit "$work/$order.ir" "$root/src/option/option.s" "${sources[@]}"
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$order.ir" "$work/$order"
    status=0; timeout 15 "$work/$order" || status=$?; test "$status" -eq 42
done
cat > "$work/shadow.s" <<'S'
package main
use library as lib
func main() int {
    lib := 0
    lib.make_item()
    return 42
}
S
printf 'preserve\n' > "$work/output"
cp "$work/output" "$work/saved"
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/option/option.s" "$work/library.s" "$work/shadow.s" > "$work/shadow.log" 2>&1; then
    echo 'local value incorrectly resolved as an imported function' >&2; exit 1
fi
cmp "$work/output" "$work/saved"
grep -q "has no method" "$work/shadow.log"
echo 'aliased unit call preserves its concrete generic return: PASS'
