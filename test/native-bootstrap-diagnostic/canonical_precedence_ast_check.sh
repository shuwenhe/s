#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func validate() () {
    source := "package main\nfunc bits() int { 1 | 2 ^ 3 }\nfunc comparison(int a, int b, int c) bool { a == b < c }\nfunc equality(int a, int b, int c) int { a & b == c }\n"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    if len(parsed.items) != 3 { panic("precedence functions lost") }
    switch parsed.items[0] {
        item.function(declaration): {
            expression := declaration.body.unwrap().final_expr.unwrap()
            switch expression {
                expr.binary(root): {
                    if root.op != "|" { panic("bitwise or must bind below xor") }
                    switch root.right.value { expr.binary(right): { if right.op != "^" { panic("missing nested xor") } }, _ : panic("xor association lost"), }
                }
                _ : panic("missing bitwise expression"),
            }
        }
        _ : panic("missing bitwise function"),
    }
    switch parsed.items[1] {
        item.function(declaration): {
            expression := declaration.body.unwrap().final_expr.unwrap()
            switch expression {
                expr.binary(root): {
                    if root.op != "==" { panic("equality must bind below comparison") }
                    switch root.right.value { expr.binary(right): { if right.op != "<" { panic("missing nested comparison") } }, _ : panic("comparison association lost"), }
                }
                _ : panic("missing comparison expression"),
            }
        }
        _ : panic("missing comparison function"),
    }
    switch parsed.items[2] {
        item.function(declaration): {
            expression := declaration.body.unwrap().final_expr.unwrap()
            switch expression {
                expr.binary(root): {
                    if root.op != "&" { panic("bitwise and must bind below equality") }
                    switch root.right.value { expr.binary(right): { if right.op != "==" { panic("missing nested equality") } }, _ : panic("equality association lost"), }
                }
                _ : panic("missing equality expression"),
            }
        }
        _ : panic("missing equality function"),
    }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
"$root/misc/scripts/verify_true_selfhost.sh" "$work/parser"
status=0; "$work/parser" || status=$?
test "$status" -eq 42
echo 'canonical parser matches seed operator precedence natively: PASS'
