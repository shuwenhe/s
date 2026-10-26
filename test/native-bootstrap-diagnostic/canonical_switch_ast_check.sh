#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func validate() () {
    source := "package main\nfunc unwrap(option[int] value) int { switch value { option.some(payload): return payload, option.none: { return 0 } } }\nfunc select(int value) int { switch value { 0: 40, -1: 41, _: 42, } }\nfunc assign(int value) int { result := 0; switch value { 0: result = 40, _: result = 42 }; return result }"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    switch parsed.items[0] {
        item.function(declaration): {
            value := declaration.body.unwrap().final_expr.unwrap()
            switch value {
                expr.switch(branch): {
                    if len(branch.arms) != 2 { panic("switch arms lost") }
                    switch branch.arms[0].pattern {
                        pattern.variant(variant): { if variant.path != "option.some" || len(variant.args) != 1 { panic("payload pattern lost") } }
                        _ : panic("missing variant pattern"),
                    }
                    switch branch.arms[0].expr {
                        expr.block(body): { switch body.statements[0] { stmt.return(_): (), _ : panic("arm return lost"), } }
                        _ : panic("missing arm block"),
                    }
                }
                _ : panic("missing switch"),
            }
        }
        _ : panic("missing unwrap function"),
    }
    switch parsed.items[1] {
        item.function(declaration): {
            value := declaration.body.unwrap().final_expr.unwrap()
            switch value {
                expr.switch(branch): {
                    if len(branch.arms) != 3 { panic("literal arms lost") }
                    switch branch.arms[2].pattern { pattern.wildcard(_): (), _ : panic("wildcard lost"), }
                }
                _ : panic("missing literal switch"),
            }
        }
        _ : panic("missing select function"),
    }
    switch parsed.items[2] {
        item.function(declaration): {
            statement := declaration.body.unwrap().statements[1]
            switch statement {
                stmt.expr(statement): {
                    switch statement.expr {
                        expr.switch(branch): { switch branch.arms[0].expr { expr.block(body): { switch body.statements[0] { stmt.assign(binding): { if binding.name != "result" { panic("arm assignment target lost") } }, _ : panic("arm assignment lost"), } }, _ : panic("missing assignment block"), } }
                        _ : panic("missing assignment switch"),
                    }
                }
                _ : panic("missing switch statement"),
            }
        }
        _ : panic("missing assignment function"),
    }
    invalid, failure := compile.internal.syntax.parse_source("package main\nfunc broken(int value) int { switch value { _: } }")
    if failure.message == "" { panic("missing switch arm expression accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
"$root/misc/scripts/verify_true_selfhost.sh" "$work/parser"
status=0; "$work/parser" || status=$?
test "$status" -eq 42
echo 'canonical parser retains switch patterns, payload bindings, returns and wildcard arms natively: PASS'
