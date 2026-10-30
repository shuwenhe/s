#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-type-elaboration.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.ast"; "compile.internal.syntax"; "compile.internal.mono")
func main() int {
    requests := compile.internal.mono.te_add_requests(compile.internal.mono.te_request[](), ["Box[int]", " Box[int] "], "left")
    if len(requests) != 1 { eprintln("duplicate canonical type requests"); return 90 }
    requests = compile.internal.mono.te_add_requests(requests, ["Box[int]"], "right")
    if len(requests) != 2 { eprintln("distinct package type requests merged"); return 91 }
    source, error := compile.internal.syntax.parse_source("package demo\nstruct box[T] { T value; box[T][] children }\nenum option[T] { none, some(T) }\nfunc take(option[box[int]] value) box[int] { box[int] { value: 7, children: box[int][] {} } }\n")
    if error.message != "" { return 1 }
    result := compile.internal.mono.elaborate_generic_types(source)
    if result.error != "" { return 2 }
    if len(result.file.items) != 3 { return 3 }
    if len(result.file.item_packages) != 3 { return 4 }
    switch result.file.items[0] {
        item.function(v): { if v.sig.params[0].type_name != "option__mono_boxarrintend" || v.sig.return_type.unwrap() != "box__mono_int" { return 5 } },
        _: return 6,
    }
    switch result.file.items[2] {
        item.enum(v): { if v.name != "option__mono_boxarrintend" || len(v.generics) != 0 || v.variants[1].payload.unwrap() != "box__mono_int" { return 7 } },
        _: return 8,
    }
    switch result.file.items[1] {
        item.struct(v): { if v.name != "box__mono_int" || v.fields[0].type_name != "int" || v.fields[1].type_name != "box__mono_int[]" { return 9 } },
        _: return 10,
    }
    bad, bad_error := compile.internal.syntax.parse_source("package demo\nstruct box[T] { T value }\nfunc take(box[int,string] value) {}\n")
    if compile.internal.mono.elaborate_generic_types(bad).error == "" { return 11 }
    arrays, arrays_error := compile.internal.syntax.parse_source("package demo\nstruct box[T] { T[4] fixed; T[2] prefix }\nfunc take((box[int],box[string]) values) {}\n")
    if arrays_error.message != "" { return 12 }
    array_result := compile.internal.mono.elaborate_generic_types(arrays)
    if array_result.error != "" || len(array_result.file.items) != 3 { return 13 }
    switch array_result.file.items[1] { item.struct(v): { if v.fields[0].type_name != "int[4]" || v.fields[1].type_name != "int[2]" { return 14 } }, _: return 15 }
    core, core_error := compile.internal.syntax.parse_source("package core\nstruct box[T] { T value }\n")
    client, client_error := compile.internal.syntax.parse_source("package client\nstruct Widget { int value }\nfunc take(core.box[Widget] value) {}\n")
    if core_error.message != "" || client_error.message != "" { return 16 }
    core.items = append(core.items, client.items[0]); core.items = append(core.items, client.items[1])
    core.item_packages = string[] { "core", "client", "client" }
    package_result := compile.internal.mono.elaborate_generic_types(core)
    if package_result.error != "" || len(package_result.file.items) != 3 { return 17 }
    if package_result.file.item_packages[2] != "core" { return 18 }
    switch package_result.file.items[2] { item.struct(v): { if v.fields[0].type_name != "client.Widget" { return 19 } }, _: return 20 }
    switch package_result.file.items[1] { item.function(v): { if v.sig.params[0].type_name != "core.box__mono_client.Widget" { return 21 } }, _: return 22 }
    generic, generic_error := compile.internal.syntax.parse_source("package demo\nstruct Pair[T] { T value }\nfunc id[T](T value) T { value }\nfunc wrap[U](U value) Pair[U] { Pair[U] { value: id(value) } }\nfunc entry() Pair[int] { wrap(7) }\n")
    if generic_error.message != "" { return 23 }
    switch generic.items[2] {
        item.function(f): {
            body := f.body.unwrap()
            final := body.final_expr.unwrap()
            switch final {
                expr.record(rec): {
                    switch rec.field_values[0] {
                        expr.call(call): { call.type_args = string[] { "U" }
 call.resolved_callee = option.some("id__mono_U"); call.inferred_type = option.some("U"); rec.field_values[0] = expr.call(call) },
                        _: return 24,
                    }
                    body.final_expr = option.some(expr.record(rec))
                },
                _: return 25,
            }
            f.body = option.some(body); generic.items[2] = item.function(f)
        },
        _: return 26,
    }
    switch generic.items[3] {
        item.function(f): {
            body := f.body.unwrap()
            final := body.final_expr.unwrap()
            switch final {
                expr.call(call): { call.type_args = string[] { "int" }
 call.resolved_callee = option.some("wrap__mono_int"); call.inferred_type = option.some("Pair[int]"); body.final_expr = option.some(expr.call(call)) },
                _: return 27,
            }
            f.body = option.some(body); generic.items[3] = item.function(f)
        },
        _: return 28,
    }
    specialized := compile.internal.mono.monomorphize_file(generic, compile.internal.semantic.semantic_result {})
    if specialized.invariant_errors != 0 { return 29 }
    if len(specialized.file.items) != 4 || len(specialized.file.item_packages) != 4 { return 30 }
    concrete := compile.internal.mono.elaborate_generic_types(specialized.file)
    if concrete.error != "" || len(concrete.file.items) != 4 { return 31 }
    switch concrete.file.items[1] {
        item.function(f): {
            if f.sig.name != "wrap__mono_int" || f.sig.return_type.unwrap() != "Pair__mono_int" { return 32 }
            checked_body := f.body.unwrap()
            checked_expr := checked_body.final_expr.unwrap()
            switch checked_expr {
                expr.record(rec): {
                    if rec.type_name != "Pair__mono_int" { return 33 }
                    switch rec.field_values[0] { expr.call(call): { if call.resolved_callee.unwrap() != "id__mono_int" || len(call.type_args) != 0 { return 34 } }, _: return 35 }
                },
                _: return 36,
            }
        },
        _: return 37,
    }
    return 42
}
S
# Exercise the complete production mono implementation with its exact semantic
# metadata definitions and identity/path helpers, excluding unrelated semantic gates.
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); out=Path(sys.argv[2]); text=(root/'src/cmd/compile/internal/mono/monomorphization.s').read_text()
def f(n):
 start=text.index('func '+n+'('); end=text.find('\nfunc ',start+1); return text[start:end if end>=0 else len(text)]
semantic=(root/'src/cmd/compile/internal/semantic/semantic.s').read_text()
def sf(n):
 start=semantic.index('func '+n+'('); end=semantic.find('\nfunc ',start+1); return semantic[start:end if end>=0 else len(semantic)]
parts=[]
for name in ['declaration_kind','declaration_ref','const_binding','function_binding','semantic_result','semantic_error']:
 marker=('enum ' if name=='declaration_kind' else 'struct ')+name+' {'
 start=semantic.index(marker); end=semantic.index('\n}',start)+2; parts.append(semantic[start:end])
(out/'semantic_metadata.s').write_text('package compile.internal.semantic\nimport ("compile.internal.ast"; "std.prelude")\n'+'\n'.join(parts+[sf('declaration_ref_equal'),sf('qualified_expr_path'),sf('qualified_package_part'),sf('find_last_char')]))

PY
"$root/bin/s_seed" --compile-native-unit "$work/test.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/fs/fs.s" "$root/src/cmd/compile/internal/ast/ast.s" "$root/src/cmd/compile/internal/parser/syntax/syntax.s" "$root/src/cmd/compile/internal/parser/syntax/canonical_parser.s" "$root/src/cmd/compile/internal/typesys/typesys.s" "$work/semantic_metadata.s" "$root/src/cmd/compile/internal/mono/monomorphization.s" "$root/src/cmd/compile/internal/mono/type_elaboration.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/test.ir" "$work/test"
status=0; "$work/test" || status=$?; echo "native-status=$status"; test "$status" -eq 42
echo 'reachable generic records/enums elaborate natively: PASS'
