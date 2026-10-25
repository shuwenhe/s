#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-ir-stmt.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.s" <<'S'
package main
import ("std.option"; "compile.internal.ir.ast")
func integer(expr_ir value) int { switch value { expr_ir.int(number): number, _ : -1 } }
func validate() () {
    literal := expr_ir.int(42)
    declaration := make_let_stmt("item", option.some("int"), literal)
    assignment := make_assign_stmt("item", literal)
    increment := make_increment_stmt("item")
    expression := make_expr_stmt(literal)
    returned := make_return_stmt(option.some(literal))
    body := block_ir { statements: [declaration, assignment, increment, expression, returned], final_expr: option.none }
    condition := expr_ir.bool(true)
    loop := make_cfor_stmt(assignment, condition, increment, body)
    switch declaration {
        stmt_ir.let(value): { if value.name != "item" || value.type_name.unwrap() != "int" || integer(value.value) != 42 { panic("wrong let") } },
        _ : panic("missing let"),
    }
    switch assignment {
        stmt_ir.assign(value): { if value.name != "item" || integer(value.value) != 42 { panic("wrong assign") } },
        _ : panic("missing assign"),
    }
    switch increment {
        stmt_ir.increment(value): { if value.name != "item" { panic("wrong increment") } },
        _ : panic("missing increment"),
    }
    switch expression {
        stmt_ir.expr(value): { if integer(value.expr) != 42 { panic("wrong expression") } },
        _ : panic("missing expression"),
    }
    switch returned {
        stmt_ir.return_stmt(value): { if integer(value.value.unwrap()) != 42 { panic("wrong return") } },
        _ : panic("missing return"),
    }
    switch loop {
        stmt_ir.cfor(value): { if len(value.body.statements) != 5 { panic("wrong loop body") } },
        _ : panic("missing loop"),
    }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$root/src/cmd/compile/internal/ir/ast.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'native IR statement constructors preserve all six variants and concrete payloads: PASS'
