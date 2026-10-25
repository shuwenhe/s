#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-mono-body.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:])
text=(root/'src/cmd/compile/internal/mono/monomorphization.s').read_text()
start=text.index('func no_mono_expr(');end=text.index('\nfunc finalize_monomorphized_function(',start+1)
lower=(root/'src/cmd/compile/internal/ir/lower.s').read_text()
a=lower.index('func no_lower_function(');b=lower.index('\nfunc ',a+1)
(work/'lower.s').write_text('package compile.internal.ir\nimport ("std.option"; "compile.internal.ast")\n'+lower[a:b])
(work/'mono.s').write_text('package compile.internal.mono\nimport ("std.option"; "std.prelude"; "compile.internal.ast")\n'+text[start:end])
PY
cat > "$work/main.s" <<'S'
package main
import ("std.option"; "compile.internal.ast"; "compile.internal.mono")
func validate() () {
    picked := compile.internal.ir.no_lower_function()
    if picked.is_some() { panic("picked function initially populated") }
    signature := compile.internal.ast.function_sig { name: "chosen", generics: string[](), params: compile.internal.ast.param[](), return_type: option.none }
    picked = option.some(compile.internal.ast.function_decl { sig: signature, body: option.none, is_public: false })
    switch picked {
        option.some(value): { if value.sig.name != "chosen" { panic("lost selected function") } },
        option.none: panic("missing selected function"),
    }
    body := compile.internal.mono.no_mono_body()
    if body.is_some() { panic("empty body is some") }
    body = option.some(compile.internal.ast.block_expr {
        statements: compile.internal.ast.stmt[](), final_expr: option.none, inferred_type: option.none,
    })
    if body.is_none() { panic("populated body is none") }
    expression := compile.internal.mono.no_mono_expr()
    boxed_expression := compile.internal.mono.no_mono_box_expr()
    boxed_statement := compile.internal.mono.no_mono_box_stmt()
    if expression.is_some() || boxed_expression.is_some() || boxed_statement.is_some() { panic("nonempty initial option") }
    literal := compile.internal.ast.expr.int(compile.internal.ast.int_expr { value: "42", inferred_type: option.none })
    expression = option.some(literal)
    boxed_expression = option.some(std.prelude.box(literal))
    statement := compile.internal.ast.stmt.expr(compile.internal.ast.expr_stmt { expr: literal })
    boxed_statement = option.some(std.prelude.box(statement))
    if expression.is_none() || boxed_expression.is_none() || boxed_statement.is_none() { panic("lost AST payload") }
    switch body {
        option.some(value): { if len(value.statements) != 0 { panic("wrong block payload") } },
        option.none: panic("lost body"),
    }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/prelude/prelude.s" "$root/src/option/option.s" "$root/src/cmd/compile/internal/ast/ast.s" "$work/mono.s" "$work/lower.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'production monomorphized body option preserves concrete block type: PASS'
