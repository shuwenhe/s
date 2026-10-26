#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-cast.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func check_cast(expr value) () {
    switch value {
        expr.call(converted): {
            if len(converted.args) != 1 { panic("cast operand lost") }
            switch converted.callee.value {
                expr.name(target): { if target.name != "int" { panic("cast target lost") } }
                _: panic("cast target missing"),
            }
            switch converted.args[0] {
                expr.bool(operand): { if !operand.value { panic("cast operand changed") } }
                _: panic("cast operand missing"),
            }
        }
        _: panic("conversion AST missing"),
    }
}
func returned(function_decl declaration) expr {
    statements := declaration.body.unwrap().statements
    switch statements[0] {
        stmt.return(value): return value.value.unwrap(),
        _: panic("return missing"),
    }
    return expr.int(compile.internal.ast.int_expr { value: "0" })
}
func validate() () {
    source := "package main\nfunc convert() int { return true as int }\nfunc precedence() int { return 1 + (true as int) * 2 }\n"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" || len(parsed.items) != 2 { panic("as conversion rejected") }
    switch parsed.items[0] {
        item.function(declaration): check_cast(returned(declaration)),
        _: panic("function missing"),
    }
    switch parsed.items[1] {
        item.function(declaration): {
            value := returned(declaration)
            switch value {
                expr.binary(sum): {
                    if sum.op != "+" { panic("cast precedence changed addition") }
                    switch sum.right.value {
                        expr.binary(product): {
                            if product.op != "*" { panic("cast precedence changed multiplication") }
                            check_cast(product.left.value)
                        }
                        _: panic("product missing"),
                    }
                }
                _: panic("sum missing"),
            }
        }
        _: panic("function missing"),
    }
    ignored, invalid := compile.internal.syntax.parse_source("package main\nfunc bad() int { return true as }\n")
    if invalid.message == "" { panic("missing conversion type accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
status=0; timeout 20 "$work/parser" || status=$?
if [ "$status" -ne 42 ]; then echo "canonical as conversion: expected42, got$status" >&2; exit 1; fi
echo 'canonical as conversions retain type, operand, precedence and type errors: PASS'
