#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-mir-box.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:]);s=(root/'src/cmd/compile/internal/mir/mir.s').read_text()
def function(name):
 a=s.index('func '+name+'(');b=s.find('\nfunc ',a+1);return s[a:b if b>=0 else len(s)]+'\n'
(work/'mir.s').write_text('package compile.internal.mir\nimport ("std.option"; "compile.internal.ast")\n'+s[s.index('enum mir_projection_kind {'):s.index('struct mir_point {')]+''.join(function(n) for n in ['mir_place_from_expr','mir_append_ownership_semantics_from_stmt','mir_append_ownership_semantics_from_expr','mir_expr_type_name','mir_callee_name']))
PY
cat > "$work/main.s" <<'S'
package main
import ("std.option"; "std.prelude"; "compile.internal.ast"; "compile.internal.mir")
func validate() () {
    callee := expr.name(name_expr { name: "box", inferred_type: option.none })
    call := expr.call(call_expr { callee: std.prelude.box(callee), args: expr[](), inferred_type: option.none, resolved_callee: option.none, type_args: string[]() })
    if compile.internal.mir.mir_expr_type_name(call) != "box[unknown]" { panic("missing box call type") }
    regular := expr.name(name_expr { name: "regular", inferred_type: option.none })
    typed := expr.call(call_expr { callee: std.prelude.box(regular), args: expr[](), inferred_type: option.some("int"), resolved_callee: option.none, type_args: string[]() })
    if compile.internal.mir.mir_expr_type_name(typed) != "int" { panic("lost inferred call type") }
    name := expr.name(name_expr { name: "owner", inferred_type: option.none })
    member := expr.member(member_expr { target: std.prelude.box(name), member: "items", inferred_type: option.none })
    index := expr.int(int_expr { value: "0", inferred_type: option.none })
    indexed := expr.index(index_expr { target: std.prelude.box(member), index: std.prelude.box(index), inferred_type: option.none })
    place := compile.internal.mir.mir_place_from_expr(indexed)
    if place.root != "owner" || len(place.projections) != 2 { panic("lost box target") }
    if place.projections[0].value != "items" || place.projections[1].value != "0" { panic("wrong projection") }
    borrowed := expr.borrow(borrow_expr { target: std.prelude.box(name), mutable: true, inferred_type: option.none })
    statements := compile.internal.mir.mir_statement[]()
    compile.internal.mir.mir_append_ownership_semantics_from_expr(statements, borrowed, "ref")
    compile.internal.mir.mir_append_ownership_semantics_from_expr(statements, indexed, "read")
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/prelude/prelude.s" "$root/src/option/option.s" "$root/src/cmd/compile/internal/ast/ast.s" "$work/mir.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'production MIR projections and ownership recursion read concrete box payloads: PASS'
