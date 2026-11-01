#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
extern "intrinsic" func host_args() string[]
extern "intrinsic" func __host_read_to_string(string path) string
func validate() () {
    args := host_args()
    actual_source := __host_read_to_string(args[1])
    actual, actual_error := compile.internal.syntax.parse_source(actual_source)
    if actual_error.message != "" { panic(actual_error.message) }
    if len(actual.items) != 5 { panic("compiler token module declarations lost") }
    source := "package main\nfunc scan(int value) string { if value >= 2 && value != 5 { return \"yes\\n\" } else if value < 0 { return \"negative\" } else { value = value + 1 }; while value < 10 { value = value + 1 }; for value != 0 { value = value - 1 }; return \"done\" + \"!\" }\nfunc at(int[] values, int index) int { return values[index + 1] }"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    if len(parsed.items) != 2 { panic("function lost") }
    switch parsed.items[0] {
        item.function(declaration): {
            body := declaration.body.unwrap()
            if len(body.statements) != 4 { panic("control flow statements lost") }
            switch body.statements[0] {
                stmt.expr(statement): {
                    switch statement.expr {
                        expr.if(branch): {
                            if branch.else_branch.is_none() || len(branch.then_branch.statements) != 1 { panic("if branches lost") }
                            switch branch.then_branch.statements[0] {
                                stmt.return(statement): {
                                    returned := statement.value.unwrap()
                                    switch returned { expr.string(literal): { if literal.value != "yes\n" { panic("escaped string value lost") } }, _ : panic("missing escaped string"), }
                                }
                                _ : panic("missing branch return"),
                            }
                            switch branch.condition.value { expr.binary(condition): { if condition.op != "&&" { panic("precedence lost") } }, _ : panic("missing condition"), }
                        }
                        _ : panic("missing if"),
                    }
                }
                _ : panic("missing if statement"),
            }
            switch body.statements[1] { stmt.expr(statement): { switch statement.expr { expr.while(loop): { if len(loop.body.statements) != 1 { panic("while body lost") } }, _ : panic("missing while"), } }, _ : panic("missing while statement"), }
            switch body.statements[2] { stmt.expr(statement): { switch statement.expr { expr.for(loop): { if loop.condition.is_none() || len(loop.body.statements) != 1 { panic("for body lost") } }, _ : panic("missing for"), } }, _ : panic("missing for statement"), }
            switch body.statements[3] { stmt.return(statement): { returned := statement.value.unwrap(); switch returned { expr.binary(concat): { if concat.op != "+" { panic("string concatenation lost") }
                        switch concat.left.value { expr.string(literal): { if literal.value != "done" { panic("string value lost") } }, _ : panic("missing left string"), } }, _ : panic("missing string"), } }, _ : panic("missing return"), }
        }
        _ : panic("missing function"),
    }
    switch parsed.items[1] {
        item.function(declaration): {
            body := declaration.body.unwrap()
            switch body.statements[0] {
                stmt.return(statement): {
                    returned := statement.value.unwrap()
                    switch returned { expr.index(index): { switch index.index.value { expr.binary(offset): { if offset.op != "+" { panic("index expression lost") } }, _ : panic("missing index offset"), } }, _ : panic("missing index"), }
                }
                _ : panic("missing index return"),
            }
        }
        _ : panic("missing index function"),
    }
    invalid, failure := compile.internal.syntax.parse_source("package main\nfunc main() int { if true { return 1 }")
    if failure.message == "" { panic("unterminated branch accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
"$root/misc/scripts/verify_true_selfhost.sh" "$work/parser"
status=0; "$work/parser" "$root/src/cmd/compile/internal/lexer/token/token.s" || status=$?
test "$status" -eq 42
echo 'canonical parser retains control flow and string expressions natively: PASS'
