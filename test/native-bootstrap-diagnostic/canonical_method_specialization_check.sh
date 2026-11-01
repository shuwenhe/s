#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
seed=${S_SEED_COMPILER:-"$root/bin/s_seed"}
work=$(mktemp -d /tmp/s-canonical-method-specialization.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "artifacts=$work"; fi' EXIT
# Keep the real semantic consumer and its transitive function dependencies. This
# excludes proof-only semantic gates, and never substitutes checking behavior.
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re,sys
root,work=map(Path,sys.argv[1:])
source=(root/'src/cmd/compile/internal/semantic/semantic.s').read_text()
positions=list(re.finditer(r'^func ([A-Za-z_][A-Za-z_0-9]*)\(',source,re.M))
functions={m[1]:source[m.start():positions[i+1].start() if i+1<len(positions) else len(source)] for i,m in enumerate(positions)}
pending=['check_source_file_for_compile','check_source_file','declaration_ref_equal','declaration_ref_display','qualified_expr_path','find_struct_declaration','check_pattern','instantiate_type','match_type_pattern_ref','qualified_package_part','qualified_decl_part','lookup_name_type','is_unknown','pattern_is_wild']; selected=set()
while pending:
 name=pending.pop()
 if name in selected or name not in functions: continue
 selected.add(name)
 code=re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',' ',functions[name])
 pending+=re.findall(r'\b([A-Za-z_][A-Za-z_0-9]*)\s*\(',code)
(work/'semantic.s').write_text(source[:positions[0].start()]+''.join(functions[m[1]] for m in positions if m[1] in selected))
PY
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.semantic"; "compile.internal.mono"; "compile.internal.ast")
func main() int {
    source := "package demo\nstruct Pair[T] { T value }\nfunc (Pair[T] self) get() T { self.value }\nfunc main(int value) int { pair := Pair[int] { value: value }; pair.get() }\n"
    parsed, failure := compile.internal.syntax.parse_source(source)
    if failure.message != "" { eprintln(failure.message); return 1 }
    checked := compile.internal.semantic.check_source_file_for_compile(parsed, source)
    if len(checked.errors) != 0 { eprintln(checked.errors[0].message); return 2 }
    annotated := compile.internal.mono.annotate_canonical_calls(parsed, checked, source)
    if annotated.error != "" { eprintln(annotated.error); return 3 }
    specialized := compile.internal.mono.monomorphize_file(annotated.file, checked)
    if specialized.error != "" { eprintln(specialized.error); return 4 }
    if specialized.invariant_errors != 0 { eprintln("specialization invariant errors=" + std.prelude.to_string(specialized.invariant_errors)); return 5 }
    elaborated := compile.internal.mono.elaborate_generic_types(specialized.file)
    if elaborated.error != "" { eprintln(elaborated.error); return 6 }
    flattened := compile.internal.mono.flatten_canonical_methods(elaborated.file)
    if flattened.error != "" { eprintln(flattened.error); return 7 }
    main_found := false; method_found := false; i := 0
    for i < len(flattened.file.items) {
        switch flattened.file.items[i] {
            item.function(function): {
                eprintln("function=" + function.sig.name)
                if function.sig.name == "Pair__mono_int.get__mono_int" {
                    method_found = true
                    if len(function.sig.params) != 1 { return 8 }
                    if function.sig.params[0].type_name != "Pair__mono_int" { eprintln(function.sig.params[0].type_name); return 9 }
                }
                if function.sig.name == "main" {
                    main_found = true
                    switch function.body.unwrap().final_expr.unwrap() {
                        expr.call(call): {
                            if len(call.args) != 1 { eprintln("receiver operand missing"); return 10 }
                            switch call.callee.value {
                                expr.name(name): { if name.name != "demo.Pair__mono_int.get__mono_int" { eprintln("callee=" + name.name); return 11 } },
                                _: { eprintln("receiver call not flattened"); return 12 },
                            }
                        },
                        _: return 13,
                    }
                }
            },
            _: (),
        }
        i = i + 1
    }
    if !main_found || !method_found { eprintln("specialized method declaration missing"); return 14 }
    return 42
}
S
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s src/cmd/compile/internal/mono/monomorphization.s src/cmd/compile/internal/mono/canonical_annotation.s src/cmd/compile/internal/mono/type_elaboration.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$seed" --compile-native-unit "$work/test.ir" "${sources[@]}" "$work/semantic.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$seed" --emit-standalone-amd64 "$work/test.ir" "$work/test"
status=0; "$work/test" || status=$?
test "$status" -eq 42
echo 'canonical method annotation, generic specialization and explicit receiver identity: PASS'
