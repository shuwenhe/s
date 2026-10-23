#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-frontend-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "parser test artifacts: $work" >&2; fi' EXIT
S_SOURCE_ROOT="$root" "$root/src/cmd/dist/source_closure.sh" src/cmd/compile/main.s "$work/sources"
sources=()
while IFS= read -r source; do
    if head -n 1 "$root/$source" | grep -qx 'package compile.internal.parser'; then
        sources+=("$root/$source")
    fi
done < "$work/sources"
cat > "$work/main.s" <<'S'
package compile.internal.parser
func check(parser p) int {
    if p.current_token.value != "answer" { return 1 }
    if p.peek_token.token_type != token_lparen { return 2 }
    if p.current_token.column != 6 { return 3 }
    return 42
}
func check_expression(ast_node node) int {
    if node.node_type != fp_ast_int_lit { return 1 }
    if node.string_data != "42" { return 2 }
    return 42
}
func main() int {
    lex := frontend_lexer_new("func answer() int { return 42 }")
    p := parser_new(lex)
    parser_next_token(p)
    checked := check(p)
    expression_lexer := frontend_lexer_new("42")
    expression_parser := parser_new(expression_lexer)
    expression := parser_parse_expression(expression_parser, prec_lowest)
    return checked + check_expression(expression) - 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "${sources[@]}" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
status=0; timeout 15 "$work/parser" || status=$?
test "$status" -eq 42
echo 'production frontend parser lexer dependency and native token advance: PASS'
