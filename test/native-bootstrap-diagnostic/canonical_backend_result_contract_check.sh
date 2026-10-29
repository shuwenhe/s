#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-backend-result-contract.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re,json,sys
root,work=map(Path,sys.argv[1:])
backend=(root/'src/cmd/compile/internal/core/backend.s').read_text()
def declaration(kind,name):
    start=re.search(r'^'+kind+r' '+re.escape(name)+r'\b',backend,re.M).start()
    depth=0
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/|[{}]',backend[start:]):
        if token[0]=='{': depth+=1
        elif token[0]=='}':
            depth-=1
            if depth==0: return backend[start:start+token.end()]+'\n'
    raise RuntimeError('unterminated declaration '+name)
names=['ok_write_ops','fail_write_ops','ok_value','fail_value','ok_unit','fail_unit','ok_int','fail_int']
fixture='package compile.internal\nimport "std.result"\n'
for name in ['backend_error','write_op','unit_value','fn_map_entry_value','channel_handle_value','owned_box_value']:
    fixture+=declaration('struct',name)
fixture+=declaration('enum','value')
fixture+=''.join(declaration('func',name) for name in names)
result_enum=(root/'src/result/result.s').read_text().split('\nfunc ',1)[0]+'\n'
callers='''
func use_writes(write_op[] payload) result[write_op[],backend_error] { return ok_write_ops(payload) }
func use_write_error() result[write_op[],backend_error] { return fail_write_ops("write failed") }
func use_value(value payload) result[value,backend_error] { return ok_value(payload) }
func use_value_error() result[value,backend_error] { return fail_value("value failed") }
func use_unit() result[(),backend_error] { return ok_unit() }
func use_unit_error() result[(),backend_error] { return fail_unit("unit failed") }
func use_int(int payload) result[int,backend_error] { return ok_int(payload) }
func use_int_error() result[int,backend_error] { return fail_int("int failed") }
func main() int { return 0 }
'''
(work/'helpers.s').write_text(fixture)
consumers=['write_result_is_err','write_result_error','write_result_value','value_result_is_err','value_result_error','value_result_value','unit_result_is_err','unit_result_error','int_result_is_err','int_result_error','int_result_value']
(work/'consumers.s').write_text('package compile.internal\nimport "std.result"\n'+''.join(declaration('func',name) for name in consumers))
(work/'result.s').write_text(result_enum)
source=fixture+callers+result_enum
# Reuse the production semantic checker, retaining its dependency closure.
s=(root/'src/cmd/compile/internal/semantic/semantic.s').read_text()
positions=list(re.finditer(r'^func ([A-Za-z_][A-Za-z_0-9]*)\(',s,re.M)); functions={m[1]:s[m.start():positions[i+1].start() if i+1<len(positions) else len(s)] for i,m in enumerate(positions)}
needed=['check_source_file_for_compile','check_source_file','declaration_ref_equal','declaration_ref_display','find_struct_declaration','check_pattern','instantiate_type','match_type_pattern_ref','qualified_package_part','qualified_decl_part','lookup_name_type','is_unknown','pattern_is_wild'];selected=set()
while needed:
    name=needed.pop()
    if name in selected or name not in functions: continue
    selected.add(name)
    code=re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',' ',functions[name]);needed+=re.findall(r'\b([A-Za-z_][A-Za-z_0-9]*)\s*\(',code)
(work/'semantic.s').write_text(s[:positions[0].start()]+''.join(functions[m[1]] for m in positions if m[1] in selected))
base='package main\nstruct Failure { string message }\nfunc main() int { return 0 }\n'
negatives=[
    'func wrong(int input) (int,Failure) { return result.ok(input) }',
    'func wrong() (int,Failure) { return result.err(Failure { message: "bad" }) }',
    'func wrong(result[int,Failure] input) (int,Failure) { return input }',
    'func wrong(int input) result[int,Failure] { return input, Failure { message: "" } }',
    'func wrong() result[int,Failure] { return result.ok(true) }',
    'func wrong() result[int,Failure] { return result.err("bad") }',
]
positive='func pair(int input) (int,Failure) { return input, Failure { message: "" } }'
checks='    contract := \"\"\n'
for i in range(0,len(source),300): checks+='    contract = contract + '+json.dumps(source[i:i+300])+'\n'
checks+='    check(contract, true)\n'
checks+='    check('+json.dumps(base+positive+'\n'+result_enum)+', true)\n'
for negative in negatives: checks+='    check('+json.dumps(base+negative+'\n'+result_enum)+', false)\n'
main='''package main
import ("compile.internal.syntax"; "compile.internal.semantic")
func check(string source, bool valid) () {
    parsed, error := compile.internal.syntax.parse_source(source)
    if error.message != "" { panic(error.message) }
    checked := compile.internal.semantic.check_source_file_for_compile(parsed, source)
    if valid && len(checked.errors) != 0 { eprintln(checked.errors[0].code + ": " + checked.errors[0].message); panic("valid result contract rejected") }
    if !valid {
        mismatch := false
        i := 0
        for i < len(checked.errors) {
            if checked.errors[i].code == "e3008" { mismatch = true }
            if checked.errors[i].code == "e3011" { panic("invalid fixture has a missing entry/name") }
            i = i + 1
        }
        if !mismatch { panic("tuple/result or payload mismatch not diagnosed") }
    }
}
func main() int {
'''+checks+'''    return 42
}
'''
(work/'main.s').write_text(main)
PY
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "${sources[@]}" "$work/semantic.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
status=0; timeout 60 "$work/main" || status=$?
test "$status" -eq 42
cat > "$work/runtime.s" <<'S'
package compile.internal
import "std.result"
func payload_number(value payload) int {
    return switch payload { value::int(number): number, _: 0, }
}
func main() int {
    op := write_op { fd: 2, text: "payload" }
    writes := ok_write_ops([op])
    if write_result_is_err(writes) { return 1 }
    ops := write_result_value(writes)
    if len(ops) != 1 || ops[0].fd != 2 || ops[0].text != "payload" { return 2 }
    write_failure := fail_write_ops("write error")
    if !write_result_is_err(write_failure) { return 3 }
    if write_result_error(write_failure).message != "write error" { return 4 }
    payload := ok_value(value.int(42))
    if value_result_is_err(payload) { return 5 }
    if payload_number(value_result_value(payload)) != 42 { return 6 }
    value_failure := fail_value("value error")
    if !value_result_is_err(value_failure) { return 7 }
    if value_result_error(value_failure).message != "value error" { return 8 }
    if unit_result_is_err(ok_unit()) { return 9 }
    unit_failure := fail_unit("unit error")
    if !unit_result_is_err(unit_failure) { return 10 }
    if unit_result_error(unit_failure).message != "unit error" { return 11 }
    integer := ok_int(42)
    if int_result_is_err(integer) { return 12 }
    if int_result_value(integer) != 42 { return 13 }
    int_failure := fail_int("int error")
    if !int_result_is_err(int_failure) { return 14 }
    if int_result_error(int_failure).message != "int error" { return 15 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/runtime.ir" "$work/helpers.s" "$work/consumers.s" "$work/result.s" "$work/runtime.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/runtime.ir" "$work/runtime"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/runtime"
status=0; timeout 10 "$work/runtime" || status=$?
test "$status" -eq 42
echo 'canonical backend result contract: actual eight helpers and callers, true tuple returns, strict tuple/result and payload rejection: PASS'
