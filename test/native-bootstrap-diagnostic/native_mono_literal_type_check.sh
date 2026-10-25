#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-mono-literal.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:])
source=(root/'src/cmd/compile/internal/mono/monomorphization.s').read_text()
ast=(root/'src/cmd/compile/internal/ast/ast.s').read_text()
# Keep the production collection branches and schemas; the reduced enum
# makes recursive array/map validation independently executable.
start=source.index('func verify_expr_no_generics(')
end=source.index('\nfunc verify_call_no_generics(',start)
body=source[start:end]
body=body[body.index('        expr.array(v) :'):]
helpers=source[source.index('func verify_optional_type_no_generics('):source.index('\nfunc substitute_type(')]
schemas=ast[ast.index('struct array_literal {'):ast.index('enum expr {')]
(work/'mono.s').write_text('''package main
import "std.option"
'''+schemas+'''enum expr { array(array_literal), map(map_literal), }
func verify_expr_no_generics(expr value) int {
    switch value {
'''+body+helpers+'''
func validate() () {
    good := expr.array(array_literal { type_text: option.some("int"), items: expr[]() })
    bad := expr.array(array_literal { type_text: option.some("T"), items: [good] })
    entry := map_entry { key: good, value: bad }
    nested := expr.map(map_literal { type_text: option.some("map[string]U"), entries: [entry] })
    inferred := expr.array(array_literal { type_text: option.none, items: [nested] })
    if verify_expr_no_generics(good) != 0 { panic("concrete array rejected") }
    if verify_expr_no_generics(bad) != 1 { panic("generic array accepted") }
    if verify_expr_no_generics(nested) != 2 { panic("map or nested generic accepted") }
    if verify_expr_no_generics(inferred) != 2 { panic("inferred collection lost nested errors") }
}
func main() int { validate(); return 42 }
''')
PY
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$work/mono.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'production collection verification reads type_text and preserves nested generic errors: PASS'
