#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func validate() () {
    source := "package main\nfunc values() int[] { int[]{1, 2 + 3,} }\nfunc empty() string[] { string[]() }\nfunc prefix() int[] { []int{4,5} }\nfunc plain() int[] { [6,7] }"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    if len(parsed.items) != 4 { panic("array functions lost") }
    i := 0
    for i < 4 {
        switch parsed.items[i] {
            item.function(declaration): {
                value := declaration.body.unwrap().final_expr.unwrap()
                switch value {
                    expr.array(array): {
                        if i == 1 { if len(array.items) != 0 || array.type_text.unwrap() != "string[]" { panic("empty array type lost") } }
                        else if len(array.items) != 2 { panic("array elements lost") }
                        if i == 0 && array.type_text.unwrap() != "int[]" { panic("suffix array type lost") }
                        if i == 2 && array.type_text.unwrap() != "[]int" { panic("prefix array type lost") }
                        if i == 3 && array.type_text.is_some() { panic("untyped array gained type") }
                    }
                    _ : panic("missing array literal"),
                }
            }
            _ : panic("missing array function"),
        }
        i = i + 1
    }
    invalid, failure := compile.internal.syntax.parse_source("package main\nfunc broken() int[] { int[]{1,,2} }")
    if failure.message == "" { panic("missing array element accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
"$root/misc/scripts/verify_true_selfhost.sh" "$work/parser"
status=0; "$work/parser" || status=$?
test "$status" -eq 42
echo 'canonical parser retains typed, untyped and empty array literals natively: PASS'
