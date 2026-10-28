#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
seed=${S_SEED_COMPILER:-"$root/bin/s_seed"}
work=$(mktemp -d /tmp/s-canonical-generic-production.XXXXXX)
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
pending=['check_source_file','declaration_ref_equal','declaration_ref_display','qualified_expr_path','find_struct_declaration','check_pattern','instantiate_type','match_type_pattern_ref','qualified_package_part','qualified_decl_part','lookup_name_type','is_unknown','pattern_is_wild']; selected=set()
while pending:
 name=pending.pop()
 if name in selected or name not in functions: continue
 selected.add(name)
 code=re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',' ',functions[name])
 pending+=re.findall(r'\b([A-Za-z_][A-Za-z_0-9]*)\s*\(',code)
(work/'semantic.s').write_text(source[:positions[0].start()]+''.join(functions[m[1]] for m in positions if m[1] in selected))
codegen=(root/'src/cmd/compile/internal/codegen/amd64_program.s').read_text()
start=codegen.index('func amd64_integer('); end=codegen.index('\nfunc ',start+1)
(work/'helpers.s').write_text('package compile.internal\nextern "intrinsic" func runtime_env_get(string key, string fallback) string\n'+codegen[start:end])
PY
cat > "$work/main.s" <<'S'
package main
import ("compile.internal")
func main() int {
    plain := compile.internal.canonical_source_to_mir("package demo\nfunc helper(int value) int { value + 1 }\nfunc main(int value) int { helper(value) }\n")
    if plain.error != "" { eprintln(plain.error); return 1 }
    if len(plain.program.functions) != 2 { return 2 }
    source := "package demo\nstruct box[T] { T value }\nfunc identity[T](T value) T { value }\nfunc wrap[U](U value) box[U] { box[U] { value: identity(value) } }\nfunc main(int value) int { result := wrap(value); return result.value }\n"
    generic := compile.internal.canonical_source_to_mir(source)
    if generic.error != "" { eprintln(generic.error); return 3 }
    if len(generic.program.functions) != 3 || len(generic.program.records) != 1 { return 4 }
    if generic.program.records[0].symbol != "demo.box__mono_int" || generic.program.records[0].field_types[0] != "int" { return 5 }
    wrap_found := false; identity_found := false; i := 0
    for i < len(generic.program.functions) {
        function := generic.program.functions[i]
        if function.symbol == "demo.wrap__mono_int" { wrap_found = true }
        if function.symbol == "demo.identity__mono_int" { identity_found = true }
        i = i + 1
    }
    if !wrap_found || !identity_found { return 6 }
    method_source := "package demo\nstruct Pair[T] { T value }\nfunc (Pair[T] self) get() T { self.value }\nfunc main(int value) int { pair := Pair[int] { value: value }; pair.get() }\n"
    method := compile.internal.canonical_source_to_mir(method_source)
    if method.error != "" { eprintln(method.error); return 13 }
    if len(method.program.functions) != 2 || len(method.program.records) != 1 { return 14 }
    if method.program.functions[1].symbol != "demo.Pair__mono_int.get__mono_int" || len(method.program.functions[1].params) != 1 { return 15 }
    intrinsic_source := "package demo\nimport \"std.prelude\"\nfunc main() int { std.prelude.len(\"abc\") + std.prelude.len(int[] { 1, 2 }) }\npackage std.prelude\nfunc len[t](t value) int { __runtime_len(value) }\nextern \"intrinsic\" func __runtime_len[t](t value) int\n"
    intrinsic := compile.internal.canonical_source_to_mir(intrinsic_source)
    if intrinsic.error != "" { eprintln(intrinsic.error); return 8 }
    if len(intrinsic.program.functions) != 5 { return 9 }
    string_wrapper := false; array_wrapper := false; i = 0
    for i < len(intrinsic.program.functions) {
        function := intrinsic.program.functions[i]
        if function.symbol == "std.prelude.__runtime_len__mono_string" {
            if function.external || len(function.blocks) != 1 || function.blocks[0].instructions[0].op != "string_len" { return 10 }
            string_wrapper = true
        }
        if function.symbol == "std.prelude.__runtime_len__mono_intarrend" {
            if function.external || len(function.blocks) != 1 || function.blocks[0].instructions[0].op != "array_len" { return 11 }
            array_wrapper = true
        }
        i = i + 1
    }
    if !string_wrapper || !array_wrapper { return 12 }
    rejected := compile.internal.canonical_source_to_mir("package demo\nstruct box[T] { T value }\nfunc main(box[int,string] value) int { 0 }\n")
    if rejected.error == "" { return 7 }
    return 42
}
S
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s src/cmd/compile/internal/mono/monomorphization.s src/cmd/compile/internal/mono/type_elaboration.s src/cmd/compile/internal/mono/canonical_annotation.s src/cmd/compile/internal/mir/program.s src/cmd/compile/internal/mir/program_enum.s src/cmd/compile/internal/ir/program_lower.s src/cmd/compile/internal/ir/program_environment.s src/cmd/compile/internal/ir/program_payload.s src/cmd/compile/internal/ir/program_enum.s src/cmd/compile/internal/compiler/canonical_source.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$seed" --compile-native-unit "$work/test.ir" "${sources[@]}" "$work/semantic.s" "$work/helpers.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$seed" --emit-standalone-amd64 "$work/test.ir" "$work/test"
status=0; "$work/test" || status=$?
test "$status" -eq 42 || { echo "native-status=$status"; exit 1; }
echo 'production source -> semantic -> generic function/type elaboration -> MIR: PASS'
