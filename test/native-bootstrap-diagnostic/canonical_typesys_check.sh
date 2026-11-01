#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-typesys.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import "compile.internal.typesys"
func main() int {
    if compile.internal.typesys.parse_type("  int  ") != "int" { return 10 }
    if compile.internal.typesys.is_builtin_primitive("Code") { return 11 }
    if !compile.internal.typesys.is_builtin_primitive(" int ") { return 12 }
    tuple := compile.internal.typesys.parse_type_ref("(int, string)")
    if tuple.base != "result" || len(tuple.args) != 2 { return 13 }
    if tuple.args[0] != "int" || tuple.args[1] != "string" { return 14 }
    array := compile.internal.typesys.parse_type_ref("int[4]")
    if !array.is_array || array.array_len != "4" || array.base != "int" { return 15 }
    borrow := compile.internal.typesys.parse_type_ref("&mut int[]")
    if !borrow.is_ref || !borrow.is_mut_ref || !borrow.is_slice || borrow.base != "int" { return 16 }
    if !compile.internal.typesys.rules_consistent() { return 17 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/prelude/prelude.s" "$root/src/cmd/compile/internal/typesys/typesys.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical type parsing terminates and preserves tuple/array/reference shapes: PASS'
