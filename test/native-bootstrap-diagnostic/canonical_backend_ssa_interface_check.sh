#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-backend-ssa-interface.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re,json,sys
root,work=map(Path,sys.argv[1:])
backend=(root/'src/cmd/compile/internal/core/backend.s').read_text()
ssa=(root/'src/cmd/compile/internal/ssa/ssa_core.s').read_text()
abi=(root/'src/cmd/compile/internal/abi/abiutils.s').read_text()
def header(source,name):
    start=re.search(r'^func '+re.escape(name)+r'\(',source,re.M).start()
    return 'extern "intrinsic" '+source[start:source.index('{',start)].strip()+'\n'
def rhs(variable): return re.search(r'^    '+variable+r' := ([^\n]+)',backend,re.M)[1]
abi_names=['in_registers_used','out_registers_used','spill_area_size','arg_width','info_string']
abi_calls=[]
for name in abi_names:
    # Read the real backend call site, not a separately maintained wrapper.
    call=re.search(r'(?<![A-Za-z_])((?:[A-Za-z_]\w*\.)*'+name+r'|abiutils_'+name+r')\(abi_info\)',backend)
    if not call: raise RuntimeError('missing ABI call '+name)
    abi_calls.append(call[0])
source='''package compile.internal
extern "intrinsic" func runtime_env_get(string key, string fallback) string
struct midend_result { string optimized_mir_text }
func probe(compile.internal.mir.mir_graph graph, midend_result midend) int {
    dominant_margin := 0
    arch := ARCH
    ssa_program := BUILDER
    ssa_text := TEXT
    debug_map := DEBUG
    if ssa_text == "" || debug_map == "" { return 1 }
    return 42
}
func probe_abi(compile.internal.abi.abi_param_result_info abi_info) int {
    registers := ABI0 + ABI1 + ABI2 + ABI3
    summary := ABI4
    if summary == "" { return registers }
    return 42
}
func main() int { return 0 }
package compile.internal.mir
struct mir_graph {}
package compile.internal.ssa_core
struct ssa_program {}
'''
for marker,value in [('ARCH',rhs('arch')),('BUILDER',rhs('ssa_program')),('TEXT',rhs('ssa_text')),('DEBUG',rhs('debug_map'))]: source=source.replace(marker,value)
for i,call in enumerate(abi_calls):source=source.replace('ABI'+str(i),call)
source+=''.join(header(ssa,n) for n in ['build_pipeline_with_graph_hints_and_margin','dump_pipeline','dump_debug_map'])
source+='package compile.internal.abi\nstruct abi_param_result_info {}\n'+''.join(header(abi,n) for n in abi_names)
(work/'contract.s').write_text(source)
# Extract production semantic dependencies; only the test record schemas above
# are isolated. API declarations and backend call expressions come from source.
s=(root/'src/cmd/compile/internal/semantic/semantic.s').read_text();positions=list(re.finditer(r'^func ([A-Za-z_][A-Za-z_0-9]*)\(',s,re.M));functions={m[1]:s[m.start():positions[i+1].start() if i+1<len(positions) else len(s)] for i,m in enumerate(positions)}
needed=['check_source_file_for_compile','check_source_file','declaration_ref_equal','declaration_ref_display','find_struct_declaration','check_pattern','instantiate_type','match_type_pattern_ref','qualified_package_part','qualified_decl_part','lookup_name_type','is_unknown','pattern_is_wild'];selected=set()
while needed:
    name=needed.pop()
    if name in selected or name not in functions:continue
    selected.add(name);code=re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',' ',functions[name]);needed+=re.findall(r'\b([A-Za-z_][A-Za-z_0-9]*)\s*\(',code)
(work/'semantic.s').write_text(s[:positions[0].start()]+''.join(functions[m[1]] for m in positions if m[1] in selected))
main='''package main
import ("compile.internal.syntax"; "compile.internal.semantic")
func check(string source, bool valid) () {
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    checked := compile.internal.semantic.check_source_file_for_compile(parsed, source)
    if valid && len(checked.errors) != 0 { eprintln(checked.errors[0].code + ": " + checked.errors[0].message); panic("backend interface mismatch") }
    if !valid && len(checked.errors) == 0 { panic("invalid SSA interface accepted") }
}
func main() int {
    source := ""
'''
for i in range(0,len(source),300):main+='    source = source + '+json.dumps(source[i:i+300])+'\n'
main+='    check(source, true)\n'
# Wrong argument types, wrong result use and obsolete names remain rejected.
negatives=[
 'package main\nfunc main() int { return api.dump_pipeline(true) }\npackage api\nstruct pipeline {}\nextern "intrinsic" func dump_pipeline(pipeline input) string',
 'package main\nfunc main() int { return api.dump_pipeline(api.pipeline {}) }\npackage api\nstruct pipeline {}\nextern "intrinsic" func dump_pipeline(pipeline input) string',
 'package main\nfunc main() string { return api.dump_ssa_pipeline(api.pipeline {}) }\npackage api\nstruct pipeline {}\nextern "intrinsic" func dump_pipeline(pipeline input) string',
]
for negative in negatives:main+='    check('+json.dumps(negative)+', false)\n'
main+='    return 42\n}\n';(work/'main.s').write_text(main)
PY
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "${sources[@]}" "$work/semantic.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
status=0; timeout 60 "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical backend interfaces: real SSA/ABI declarations and callers, strict names/arguments/string results: PASS'
