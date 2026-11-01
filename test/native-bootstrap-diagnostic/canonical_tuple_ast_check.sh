#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func require_pair(expr value) () {
    switch value {
        expr.tuple(pair): { if len(pair.items) != 2 { panic("tuple arity lost") } }
        _: panic("missing tuple"),
    }
}
func validate() () {
    parsed, failure := compile.internal.syntax.parse_source("package main\nfunc pair() (int,int) { first, second := 1, 2; first, second = second, first; return first, second }")
    if failure.message != "" { panic(failure.message) }
    switch parsed.items[0] {
        item.function(declaration): {
            statements := declaration.body.unwrap().statements
            if len(statements) != 3 { panic("tuple statements lost") }
            switch statements[0] {
                stmt.multi(value): {
                    if !value.declaration || len(value.targets) != 2 { panic("multi declaration lost") }
                    require_pair(value.value)
                }
                _: panic("missing multi declaration"),
            }
            switch statements[1] {
                stmt.multi(value): { if value.declaration { panic("assignment became declaration") } }
                _: panic("missing multi assignment"),
            }
            switch statements[2] {
                stmt.return(value): require_pair(value.value.unwrap()),
                _: panic("missing return"),
            }
        }
        _: panic("missing function"),
    }
    invalid, error := compile.internal.syntax.parse_source("package main\nfunc broken() int { a, := 1; return a }")
    if error.message == "" { panic("missing target accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
"$root/misc/scripts/verify_true_selfhost.sh" "$work/parser"
status=0; "$work/parser" || status=$?
test "$status" -eq 42
echo 'canonical parser retains tuple values, returns and parallel bindings natively: PASS'
