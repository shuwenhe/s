#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func validate() () {
    source := "package main\npub extern \"intrinsic\" func host[T](\nT value\n) (T, string)\nfunc (Pair[T]* self) get(int offset) T { return self.first }\nconst limit = 42\nready := true\n"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    if len(parsed.items) != 4 { panic("declarations lost") }
    switch parsed.items[0] {
        item.function(declaration): {
            if declaration.sig.name != "host" || !declaration.is_public || declaration.body.is_some() { panic("external signature lost") }
            if declaration.extern_library != "intrinsic" { panic("external linkage lost") }
            if declaration.sig.return_type.unwrap() != "(T,string)" { panic("tuple return type lost") }
        }
        _ : panic("missing external function"),
    }
    switch parsed.items[1] {
        item.method(declaration): {
            if declaration.receiver_name != "self" || declaration.receiver_type != "Pair[T]*" || declaration.method.sig.name != "get" { panic("receiver identity lost") }
            if declaration.method.body.is_none() { panic("method body lost") }
        }
        _ : panic("missing method"),
    }
    switch parsed.items[2] { item.const(declaration): { if declaration.name != "limit" || declaration.value.is_none() { panic("constant lost") } }, _ : panic("missing constant"), }
    switch parsed.items[3] { item.var(declaration): { if declaration.name != "ready" || declaration.value.is_none() { panic("global lost") } }, _ : panic("missing global"), }
    invalid, failure := compile.internal.syntax.parse_source("package main\nextern func broken(int value) int { return value }")
    if failure.message == "" { panic("extern body accepted") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
"$root/misc/scripts/verify_true_selfhost.sh" "$work/parser"
status=0; "$work/parser" || status=$?
test "$status" -eq 42
echo 'canonical parser retains externs, receivers, constants and globals natively: PASS'
