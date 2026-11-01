#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func validate() () {
    source := "package main\nenum Code { zero, answer = 40, next, }\nfunc main(int value) int { return int(Code.answer) + value }\n"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" || parsed.pkg != "main" || len(parsed.items) != 2 { panic("canonical AST not retained") }
    switch parsed.items[0] {
        item.enum(declaration): {
            if declaration.name != "Code" || len(declaration.variants) != 3 { panic("enum declaration lost") }
            if !declaration.variants[1].has_explicit_value || declaration.variants[1].explicit_value != 40 { panic("enum discriminant lost") }
        }
        _ : panic("missing enum item"),
    }
    switch parsed.items[1] {
        item.function(declaration): {
            if declaration.sig.name != "main" || len(declaration.sig.params) != 1 || len(declaration.body.unwrap().statements) != 1 { panic("function body lost") }
        }
        _ : panic("missing function item"),
    }
    local_file, local_error := compile.internal.syntax.parse_source("package main\nfunc read(int input) int { var value = input; return value }")
    if local_error.message != "" { panic(local_error.message) }
    switch local_file.items[0] {
        item.function(declaration): {
            body := declaration.body.unwrap()
            if len(body.statements) != 2 { panic("var binding was split into expressions") }
            switch body.statements[0] {
                stmt.let(binding): { if binding.name != "value" { panic("var binding name lost") } }
                _: panic("var binding is not a declaration"),
            }
        }
        _: panic("missing var fixture function"),
    }
    invalid, failure := compile.internal.syntax.parse_source("package main\nenum Code { answer")
    if failure.message == "" { panic("malformed declaration accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
"$root/misc/scripts/verify_true_selfhost.sh" "$work/parser"
status=0; "$work/parser" || status=$?
test "$status" -eq 42
echo 'canonical parser retains enum, function body and structured parse errors natively: PASS'
