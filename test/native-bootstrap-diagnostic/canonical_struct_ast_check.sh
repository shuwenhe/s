#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-parser.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.ast")
func validate() () {
    source := "package main\npub struct Pair[T] { pub T first; rest: option[T][] }\nstruct Empty {}\nstruct Mixed { value expr; body block_expr; string field; config abi_config; sig function_sig }\n"
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    if parsed.pkg != "main" || len(parsed.items) != 3 { panic("struct AST not retained") }
    switch parsed.items[0] {
        item.struct(declaration): {
            if declaration.name != "Pair" || !declaration.is_public { panic("struct identity lost") }
            if len(declaration.generics) != 1 || declaration.generics[0] != "T" { panic("struct generics lost") }
            if len(declaration.fields) != 2 { panic("struct fields lost") }
            if declaration.fields[0].name != "first" || declaration.fields[0].type_name != "T" || !declaration.fields[0].is_public { panic("first field lost") }
            if declaration.fields[1].name != "rest" || declaration.fields[1].type_name != "option[T][]" || declaration.fields[1].is_public { panic("nested field type lost") }
        }
        _ : panic("missing struct item"),
    }
    switch parsed.items[1] {
        item.struct(declaration): { if declaration.name != "Empty" || len(declaration.fields) != 0 { panic("empty struct lost") } }
        _ : panic("missing empty struct"),
    }
    switch parsed.items[2] {
        item.struct(declaration): {
            if len(declaration.fields) != 5 { panic("mixed-order fields lost") }
            if declaration.fields[0].name != "value" || declaration.fields[0].type_name != "expr" { panic("legacy value field reversed") }
            if declaration.fields[1].name != "body" || declaration.fields[1].type_name != "block_expr" { panic("legacy body field reversed") }
            if declaration.fields[2].name != "field" || declaration.fields[2].type_name != "string" { panic("canonical field reversed") }
            if declaration.fields[3].name != "config" || declaration.fields[3].type_name != "abi_config" { panic("legacy config field reversed") }
            if declaration.fields[4].name != "sig" || declaration.fields[4].type_name != "function_sig" { panic("legacy signature field reversed") }
        }
        _ : panic("missing mixed-order struct"),
    }
    invalid, failure := compile.internal.syntax.parse_source("package main\nstruct Broken { int }")
    if failure.message == "" { panic("field without name accepted") }
    truncated, truncated_error := compile.internal.syntax.parse_source("package main\nstruct Broken { int value")
    if truncated_error.message == "" { panic("unterminated struct accepted") }
    dangling, dangling_error := compile.internal.syntax.parse_source("package main\npub")
    if dangling_error.message == "" { panic("dangling visibility accepted") }
    duplicate, duplicate_error := compile.internal.syntax.parse_source("package main\npub pub struct Pair {}")
    if duplicate_error.message == "" { panic("duplicate visibility accepted") }

    malformed, malformed_error := compile.internal.syntax.parse_source("package main\nstruct Broken { int[+*] value }")
    if malformed_error.message == "" { panic("malformed type application accepted") }
    missing, missing_error := compile.internal.syntax.parse_source("package main\nstruct Broken { Pair[int,,string] value }")
    if missing_error.message == "" { panic("missing type argument accepted") }

}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/parser.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/parser.ir" "$work/parser"
"$root/misc/scripts/verify_true_selfhost.sh" "$work/parser"
status=0; "$work/parser" || status=$?
test "$status" -eq 42
echo 'canonical parser retains public generic structs, fields and malformed-input errors natively: PASS'
