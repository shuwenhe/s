#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
seed=${S_SEED_COMPILER:-"$root/bin/s_seed"}
work=$(mktemp -d /tmp/s-canonical-source-diagnostics.XXXXXX)
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
codegen=(root/'src/cmd/compile/internal/codegen/amd64_program.s').read_text()
start=codegen.index('func amd64_integer('); end=codegen.index('\nfunc ',start+1)
(work/'helpers.s').write_text('package compile.internal\nextern "intrinsic" func runtime_env_get(string key, string fallback) string\n'+codegen[start:end])
PY
cat > "$work/main.s" <<'S'
package main
import "compile.internal"
func main() int {
    source := "package demo\nfunc main() int {\n    return true\n}\n"
    result := compile.internal.canonical_source_to_mir(source)
    if result.error == "" { return 1 }
    eprintln(result.error)
    return 0
}
S

sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s src/cmd/compile/internal/mono/monomorphization.s src/cmd/compile/internal/mono/canonical_annotation.s src/cmd/compile/internal/mono/type_elaboration.s src/cmd/compile/internal/mir/program.s src/cmd/compile/internal/mir/program_enum.s src/cmd/compile/internal/ir/program_lower.s src/cmd/compile/internal/ir/program_environment.s src/cmd/compile/internal/ir/program_payload.s src/cmd/compile/internal/ir/program_enum.s src/cmd/compile/internal/compiler/canonical_source.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$seed" --compile-native-unit "$work/test.ir" "${sources[@]}" "$work/semantic.s" "$work/helpers.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$seed" --emit-standalone-amd64 "$work/test.ir" "$work/test"
"$work/test" 2> "$work/diagnostic.txt"
cat "$work/diagnostic.txt"
rg -q -F 'canonical semantic:3:5: e3008:' "$work/diagnostic.txt"
rg -q -F 'anchor=return' "$work/diagnostic.txt"
rg -q -F '    return true' "$work/diagnostic.txt"
echo 'canonical source production diagnostics include location, anchor, and source context: PASS'
