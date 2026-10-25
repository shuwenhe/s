#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-stage5-ast.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:]);s=(root/'src/cmd/compile/internal/stage5_gate.s').read_text()
a=s.index('struct identifier_info {');b=s.index('func resolve_identifier_to_candidates(',a);q=s.index('func qualified_expr_path_gate(')
(work/'gate.s').write_text('package compile.internal.semantic\nimport ("compile.internal.ast"; "std.option"; "std.prelude")\n'+s[a:b]+s[q:])
PY
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.ast"; "compile.internal.semantic"; "std.option"; "std.prelude")
func validate() () {
    leaf := expr.name(compile.internal.ast.name_expr { name: "source", inferred_type: option.none })
    member := expr.member(compile.internal.ast.member_expr { target: std.prelude.box(leaf), member: "value", inferred_type: option.none })
    call := expr.call(compile.internal.ast.call_expr { callee: std.prelude.box(member), args: [leaf], inferred_type: option.none, resolved_callee: option.none, type_args: string[]() })
    declaration := stmt.let(compile.internal.ast.var_stmt { name: "defined", type_name: option.none, value: call })
    returned := stmt.return(compile.internal.ast.return_stmt { value: option.some(leaf) })
    body := compile.internal.ast.block_expr { statements: [declaration, returned], final_expr: option.some(leaf), inferred_type: option.none }
    identifiers := append_from_function_body(identifier_info[](), option.some(body))
    if len(identifiers) != 5 || identifiers[0].identifier_text != "source.value" || !identifiers[0].is_qualified { panic("wrong qualified identifiers") }
    i := 1
    for i < len(identifiers) {
        if identifiers[i].identifier_text != "source" || identifiers[i].is_qualified { panic("lost nested identifier") }
        i = i + 1
    }
    if len(append_from_function_body(identifier_info[](), option.none)) != 0 { panic("missing body traversed") }
    conditional := expr.if(compile.internal.ast.if_expr { condition: std.prelude.box(leaf), then_branch: body, else_branch: option.some(std.prelude.box(leaf)), inferred_type: option.none })
    array := expr.array(compile.internal.ast.array_literal { type_text: option.none, items: [conditional] })
    if len(append_from_expr(identifier_info[](), array)) != 7 { panic("conditional array identifiers lost") }
    entry := compile.internal.ast.map_entry { key: leaf, value: conditional }
    map := expr.map(compile.internal.ast.map_literal { type_text: option.none, entries: [entry] })
    if len(append_from_expr(identifier_info[](), map)) != 8 { panic("map identifiers lost") }
    step := stmt.increment(compile.internal.ast.increment_stmt { name: "source" })
    loop := expr.for(compile.internal.ast.for_expr { init: option.some(std.prelude.box(declaration)), condition: option.some(std.prelude.box(leaf)), post: option.some(std.prelude.box(step)), names: string[](), iterable: option.some(std.prelude.box(leaf)), body: body, inferred_type: option.none })
    if len(append_from_expr(identifier_info[](), loop)) != 11 { panic("loop identifiers lost") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$root/src/prelude/prelude.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/ir/ast.s" "$work/gate.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'native Stage5 traversal preserves current AST statement, call, branch, loop and collection identifiers: PASS'
