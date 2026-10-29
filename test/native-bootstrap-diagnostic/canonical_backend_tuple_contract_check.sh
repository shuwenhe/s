#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-backend-tuple-contract.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re,json,sys
root,work=map(Path,sys.argv[1:]);backend=(root/'src/cmd/compile/internal/core/backend.s').read_text()
positions=list(re.finditer(r'^func ([A-Za-z_]\w*)\(',backend,re.M));functions={m[1]:backend[m.start():positions[i+1].start() if i+1<len(positions) else len(backend)] for i,m in enumerate(positions)}
needed=['build_go_asm_bridge_artifact','validate_go_asm_bridge_artifact'];selected=set()
while needed:
    name=needed.pop()
    if name in selected or name not in functions:continue
    selected.add(name);code=re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',' ',functions[name]);needed+=re.findall(r'(?<![\w.])([A-Za-z_]\w*)\s*\(',code)
record=re.search(r'^struct backend_error \{[^}]*\}',backend,re.M)[0]
fixture='package compile.internal\n'+record+'\n'+''.join(functions[m[1]] for m in positions if m[1] in selected)
(work/'helpers.s').write_text(fixture)
prelude=(root/'src/prelude/prelude.s').read_text()
interfaces='package std.prelude\n'
for name in ['len','char_at','prelude_slice','to_string']:
    start=re.search(r'^func '+name+r'(?:\[.*?\])?\(',prelude,re.M).start();interfaces+='extern "intrinsic" '+prelude[start:prelude.index('{',start)].strip()+'\n'
source=fixture+'\nfunc main() int { return 0 }\n'+interfaces
s=(root/'src/cmd/compile/internal/semantic/semantic.s').read_text();positions=list(re.finditer(r'^func ([A-Za-z_]\w*)\(',s,re.M));functions={m[1]:s[m.start():positions[i+1].start() if i+1<len(positions) else len(s)] for i,m in enumerate(positions)}
needed=['check_source_file_for_compile','check_source_file','declaration_ref_equal','declaration_ref_display','find_struct_declaration','check_pattern','instantiate_type','match_type_pattern_ref','qualified_package_part','qualified_decl_part','lookup_name_type','is_unknown','pattern_is_wild'];selected=set()
while needed:
    name=needed.pop()
    if name in selected or name not in functions:continue
    selected.add(name);code=re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',' ',functions[name]);needed+=re.findall(r'\b([A-Za-z_]\w*)\s*\(',code)
(work/'semantic.s').write_text(s[:positions[0].start()]+''.join(functions[m[1]] for m in positions if m[1] in selected))
main='''package main
import ("compile.internal.syntax"; "compile.internal.semantic")
func main() int {
    source := ""
'''
for i in range(0,len(source),300):main+='    source = source + '+json.dumps(source[i:i+300])+'\n'
main+='''    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    checked := compile.internal.semantic.check_source_file_for_compile(parsed, source)
    if len(checked.errors) != 0 { eprintln(checked.errors[0].code + ": " + checked.errors[0].message); return 1 }
    return 42
}
''';(work/'main.s').write_text(main)
PY
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "${sources[@]}" "$work/semantic.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
status=0; timeout 90 "$work/main" || status=$?
test "$status" -eq 42
cat > "$work/runtime.s" <<'S'
package compile.internal
func main() int {
    instruction, instruction_error := translate_go_instruction_line("MOVQ $42, AX", "amd64")
    if instruction_error.message != "" || !has_substring(instruction, "movq") || !has_substring(instruction, "%rax") { return 1 }
    bad, bad_error := translate_go_instruction_line("UNSUPPORTED AX", "amd64")
    if bad_error.message == "" || bad != "" { return 2 }
    operand, operand_error := convert_go_operand_to_gas("", "amd64")
    if operand_error.message == "" || operand != "" { return 3 }
    symbol, symbol_error := parse_go_text_symbol("TEXT missing")
    if symbol_error.message == "" || symbol != "" { return 4 }
    translated, translation_error := translate_go_plan9_to_gas("amd64", "MOVQ $1, AX")
    if translation_error.message == "" || translated != "" { return 5 }
    empty, validation_error := validate_go_asm_bridge_artifact("go-asm version=1\nsyntax=plan9\nstatus=ok\ngas_preview=ret")
    if validation_error.message != "" { return 6 }
    ignored, invalid_error := validate_go_asm_bridge_artifact("")
    if invalid_error.message == "" { return 7 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/runtime.ir" "$root/src/prelude/prelude.s" "$root/src/result/result.s" "$work/helpers.s" "$work/runtime.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/runtime.ir" "$work/runtime"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/runtime"
status=0; timeout 10 "$work/runtime" || status=$?
test "$status" -eq 42
echo 'canonical backend tuple contracts: actual Go asm helpers, explicit success/error pairs and destructured callers: PASS'
