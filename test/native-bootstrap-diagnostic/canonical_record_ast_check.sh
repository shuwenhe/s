#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func validate() () {
    source := "package main\nstruct Inner { int count }\nstruct Outer { Inner inner; int value }\nfunc build(int input) Outer { Outer { inner: Inner { count: input }, value input + 1, } }\nfunc condition(bool ready) int { if ready { return 1 }; return 0 }"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    if len(parsed.items) != 4 { panic("record declarations lost") }
    switch parsed.items[2] {
        item.function(declaration): {
            expression := declaration.body.unwrap().final_expr.unwrap()
            switch expression {
                expr.record(record): {
                    if record.type_name != "Outer" || len(record.field_names) != 2 || len(record.field_values) != 2 { panic("record identity lost") }
                    if record.field_names[0] != "inner" || record.field_names[1] != "value" { panic("record fields lost") }
                    switch record.field_values[0] {
                        expr.record(inner): { if inner.type_name != "Inner" || inner.field_names[0] != "count" { panic("nested record lost") } }
                        _ : panic("missing inner record"),
                    }
                    switch record.field_values[1] { expr.binary(value): { if value.op != "+" { panic("record field expression lost") } }, _ : panic("missing field expression"), }
                }
                _ : panic("missing record literal"),
            }
        }
        _ : panic("missing record function"),
    }
    invalid, failure := compile.internal.syntax.parse_source("package main\nfunc broken() Outer { Outer { value: } }")
    if failure.message == "" { panic("missing field value accepted") }
    truncated, truncated_error := compile.internal.syntax.parse_source("package main\nfunc broken() Outer { Outer { value: 1")
    if truncated_error.message == "" { panic("unterminated record accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
"$root/misc/scripts/verify_true_selfhost.sh" "$work/parser"
status=0; "$work/parser" || status=$?
test "$status" -eq 42
echo 'canonical parser retains nested record literals and control-flow boundaries natively: PASS'
