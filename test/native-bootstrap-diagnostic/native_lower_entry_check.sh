#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-lower-entry.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:])
s=(root/'src/cmd/compile/internal/ir/lower.s').read_text()
a=s.index('func no_lower_function('); b=s.index('\nfunc ',a+1)
x=s.index('func lower_package_to_mir(');start=s.index('    fn_count :=',x);end=s.index('    graph :=',start)
body=s[start:end].replace('return mir_graph {}, "entry function not found: package has no function body"','return no_lower_function()').replace('return mir_graph {}, "entry function not found"','return no_lower_function()')
# Execute the production entry-selection prefix; MIR lowering is outside this test.
(work/'select.s').write_text('package main\nimport ("std.option"; "compile.internal.ast")\n'+s[a:b]+'\nfunc select_entry(source_file src) option[function_decl] {\n'+body+'    return picked\n}\n')
PY
cat > "$work/main.s" <<'S'
package main
import ("std.option"; "compile.internal.ast")
func no_body() option[block_expr] { return option.none }
func function(string name, bool defined) item {
    body := option.some(block_expr { statements: stmt[](), final_expr: option.none, inferred_type: option.none })
    if !defined { body = no_body() }
    sig := function_sig { name: name, generics: string[](), params: param[](), return_type: option.none }
    return item.function(function_decl { sig: sig, body: body, is_public: false })
}
func chosen(item[] items) string {
    src := source_file { pkg: "fixture", uses: use_decl[](), items: items, item_packages: string[]() }
    value := select_entry(src)
    switch value {
        option.some(selected): selected.sig.name,
        option.none: "missing",
    }
}
func validate() () {
    helper := function("helper", true)
    main := function("main", true)
    declaration := function("declared", false)
    if chosen([helper, main]) != "main" { panic("main not preferred") }
    if chosen([helper]) != "helper" { panic("fallback lost") }
    if chosen([declaration]) != "missing" { panic("declaration selected") }
    if chosen(item[]()) != "missing" { panic("empty package selected") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/prelude/prelude.s" "$root/src/option/option.s" "$root/src/cmd/compile/internal/ast/ast.s" "$work/select.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'production MIR entry selection preserves main/fallback/absent function identities: PASS'
