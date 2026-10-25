#!/usr/bin/env bash
# Execute the production matcher with primitive-spelling type dependencies.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-generic-pattern.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:]); source=(root/'src/cmd/compile/internal/semantic/semantic.s').read_text()
types=(root/'src/cmd/compile/internal/typesys/typesys.s').read_text()
def function(text,name):
    start=text.index('func '+name+'('); end=text.find('\nfunc ',start+1)
    return text[start:end if end>=0 else len(text)]+'\n'
(work/'semantic.s').write_text('package compile.internal.semantic\n'+source[source.index('struct type_binding {'):source.index('struct function_binding {')]+''.join(function(source,n) for n in ['is_generic_name','lookup_name_type','is_unknown','match_type_pattern_ref']))
(work/'types.s').write_text('package compile.internal.typesys\n'+types[types.index('struct type_ref {'):types.index('func parse_type(')]+function(types,'same_type_ref')+function(types,'same_type')+'''
func parse_type(string text) string { return text }
func parse_type_ref(string text) type_ref { return type_ref { canonical: text, base: text, args: string[]() } }
''')
PY
cat > "$work/main.s" <<'S'
package main
func main() int {
    parameter := compile.internal.typesys.type_ref { canonical: "T", base: "T", args: string[]() }
    integer := compile.internal.typesys.type_ref { canonical: "int", base: "int", args: string[]() }
    boolean := compile.internal.typesys.type_ref { canonical: "bool", base: "bool", args: string[]() }
    binding := compile.internal.semantic.type_binding { name: "T", type_name: "int" }
    bindings := [binding]
    if !compile.internal.semantic.match_type_pattern_ref(parameter, integer, ["T"], bindings) { return 1 }
    if compile.internal.semantic.match_type_pattern_ref(parameter, boolean, ["T"], bindings) { return 2 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/types.s" "$work/semantic.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'production generic matcher compares bound canonical type strings: PASS (primitive-spelling dependencies)'
