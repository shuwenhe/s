#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-c-for.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "artifacts=$work"; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func main() int {
    source := "package main\nfunc count() int { total := 0; for i := 0; i < 4; i++ { total += i }; for ; total < 9; { total += 1 }; for ;; { return total } }"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    if len(parsed.items) != 1 { return 1 }
    switch parsed.items[0] {
        item.function(function): {
            body := function.body.unwrap()
            statements := body.statements
            if len(statements) != 3 { return 2 }
            switch statements[1] {
                stmt.expr(statement): {
                    switch statement.expr {
                        expr.for(loop): {
                            if loop.init.is_none() || loop.condition.is_none() || loop.post.is_none() { return 3 }
                        }
                        _ : { return 8 },
                    }
                }
                _ : { return 9 },
            }
            switch statements[2] { stmt.expr(statement): { switch statement.expr { expr.for(loop): { if loop.init.is_some() || loop.condition.is_none() || loop.post.is_some() { return 10 } }, _ : { return 11 }, } }, _ : { return 12 }, }
            final := body.final_expr.unwrap()
            switch final { expr.for(loop): { if loop.init.is_some() || loop.condition.is_some() || loop.post.is_some() { return 13 } }, _ : { return 14 }, }
        }
        _ : { return 15 },
    }
    invalid, failure := compile.internal.syntax.parse_source("package main\nfunc bad() { for i := 0 i < 4; i++ {} }")
    if failure.message == "" { return 16 }
    missing, missing_error := compile.internal.syntax.parse_source("package main\nfunc bad() { for i := 0; i < 4 i++ {} }")
    if missing_error.message == "" { return 17 }
    legacy_source := "package main\nstruct Reader { input* package.Item }\nfunc legacy(item* package.Item, int input,) int { values := make(int[][], input); legacy(item*); switch input { case 0: first := 2; return first; case 1: return 4; default: return 7 } }"
    legacy, legacy_error := compile.internal.syntax.parse_source(legacy_source)
    if legacy_error.message != "" { panic(legacy_error.message) }
    if len(legacy.items) != 2 { return 18 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical C-style for clauses, optional clauses and malformed headers: PASS'
