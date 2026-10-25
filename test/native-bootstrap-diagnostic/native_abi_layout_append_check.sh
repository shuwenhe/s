#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
seed=${S_SEED_COMPILER:-"$root/bin/s_seed"}
work=$(mktemp -d /tmp/s-native-abi-layout-append.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "ABI layout artifacts: $work" >&2; fi' EXIT

# Compile the production layout helpers and their real prelude dependency.
# Discarding append's returned slice used to erase every generated register
# offset/type, even though the helpers still reported an advanced next offset.
cat > "$work/main.s" <<'S'
package main
func main() int {
    offsets := int[]()
    offsets = append(offsets, 3)
    empty := append_param_offsets(offsets, 8, "()")
    if len(empty.offsets) != 1 || empty.offsets[0] != 3 || empty.next != 8 { return 1 }
    scalar := append_param_offsets(offsets, 8, "int")
    if len(scalar.offsets) != 2 { return 2 }
    if scalar.offsets[0] != 3 || scalar.offsets[1] != 8 || scalar.next != 16 { return 3 }
    complex := append_param_offsets(int[](), 16, "complex128")
    if len(complex.offsets) != 2 { return 4 }
    if complex.offsets[0] != 16 || complex.offsets[1] != 24 || complex.next != 32 { return 5 }

    initial := string[]()
    initial = append(initial, "sentinel")
    zero := append_param_types(initial, "()")
    if len(zero) != 1 || zero[0] != "sentinel" { return 6 }
    integer := append_param_types(initial, "int")
    if len(integer) != 2 { return 7 }
    if integer[0] != "sentinel" || integer[1] != "int" { return 8 }
    floating := append_param_types(string[](), "float64")
    if len(floating) != 1 { return 9 }
    if floating[0] != "float" { return 10 }
    pair := append_param_types(string[](), "complex128")
    if len(pair) != 2 { return 11 }
    if pair[0] != "float" || pair[1] != "float" { return 12 }
    text := append_param_types(string[](), "string")
    if len(text) != 2 { return 13 }
    if text[0] != "ptr" || text[1] != "int" { return 14 }
    iface := append_param_types(string[](), "any")
    if len(iface) != 2 { return 15 }
    if iface[0] != "ptr" || iface[1] != "ptr" { return 16 }
    return 42
}
S
"$seed" --compile-native-unit "$work/layout.ir" \
    "$root/src/prelude/prelude.s" \
    "$root/src/cmd/compile/internal/abi/abiutils.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$seed" --emit-standalone-amd64 "$work/layout.ir" "$work/layout"
status=0
timeout 15s "$work/layout" || status=$?
if [ "$status" -ne 42 ]; then
    echo "ABI layout append check returned $status, want 42 (see numbered assertions)" >&2
    exit 1
fi
echo 'native ABI layout append preserves offsets and register types: PASS'
