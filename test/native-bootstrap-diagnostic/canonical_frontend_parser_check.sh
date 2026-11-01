#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-frontend-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import "compile.internal.parser"
func main() int {
    valid_lexer := compile.internal.parser.frontend_lexer_new("package demo\n")
    valid := compile.internal.parser.parser_new(valid_lexer)
    tree := compile.internal.parser.parser_parse_program(valid*)
    if len(valid.errors) != 0 || len(tree.children) != 1 { return 1 }
    if tree.children[0].name != "demo" { return 2 }
    invalid_lexer := compile.internal.parser.frontend_lexer_new("@")
    invalid := compile.internal.parser.parser_new(invalid_lexer)
    ignored := compile.internal.parser.parser_parse_program(invalid*)
    if len(invalid.errors) != 1 || invalid.errors[0] != "Unexpected token: @" { return 3 }
    expression_lexer := compile.internal.parser.frontend_lexer_new("@")
    expression := compile.internal.parser.parser_new(expression_lexer)
    ignored_expr := compile.internal.parser.parser_parse_primary_expression(expression*)
    if len(expression.errors) != 1 || expression.errors[0] != "Unexpected token in expression: @" { return 4 }
    return 42
}
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s" \
 "$root/src/cmd/compile/internal/parser/frontend_ast.s" \
 "$root/src/cmd/compile/internal/parser/frontend_lexer.s" \
 "$root/src/cmd/compile/internal/parser/frontend_parser.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; timeout 15 "$work/main" || status=$?
test "$status" -eq 42 || { echo "canonical frontend parser failed: exit=$status" >&2; exit 1; }
echo 'canonical native frontend parser preserves AST mutation and error messages: PASS'
