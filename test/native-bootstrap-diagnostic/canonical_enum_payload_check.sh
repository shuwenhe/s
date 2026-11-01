#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-semantic-ast.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re,sys
root,work=map(Path,sys.argv[1:])
s=(root/'src/cmd/compile/internal/semantic/semantic.s').read_text()
positions=list(re.finditer(r'^func ([A-Za-z_][A-Za-z_0-9]*)\(',s,re.M))
functions={m[1]:s[m.start():positions[i+1].start() if i+1<len(positions) else len(s)] for i,m in enumerate(positions)}
needed=['check_source_file','declaration_ref_equal','declaration_ref_display','find_struct_declaration','check_pattern','instantiate_type','match_type_pattern_ref','qualified_package_part','qualified_decl_part','lookup_name_type','is_unknown','pattern_is_wild'];selected=set()
while needed:
 name=needed.pop()
 if name in selected or name not in functions:continue
 selected.add(name)
 code=re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',' ',functions[name])
 needed+=re.findall(r'\b([A-Za-z_][A-Za-z_0-9]*)\s*\(',code)
text=s[:positions[0].start()]+''.join(functions[m[1]] for m in positions if m[1] in selected)
if __import__('os').environ.get('S_SEMANTIC_DEBUG')=='1':
 text=text.replace('    errors := left.errors + right.errors', '    eprintln("binary types=" + left.type_name + "," + right.type_name)\n    errors := left.errors + right.errors')
 text=text.replace('    result := infer_block_expr(function_decl.body.unwrap()', '    eprintln("expected return=" + expected_return)\n    result := infer_block_expr(function_decl.body.unwrap()')
 text=text.replace('    if is_unknown(left) || is_unknown(right)', '    eprintln("compatible=" + left + "," + right)\n    if is_unknown(left) || is_unknown(right)')
 text=text.replace('    recovery_anchor := resolve_recovery_anchor(source, anchor)','    eprintln(code + ": " + message + " @ " + anchor)\n    recovery_anchor := resolve_recovery_anchor(source, anchor)')
(work/'semantic.s').write_text(text)
PY
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.semantic")
func check(string source, bool valid) () {
    file, failure := compile.internal.syntax.parse_source(source + "\nfunc main() int { return 0 }")
    if failure.message != "" { panic(failure.message) }
    result := compile.internal.semantic.check_source_file(file, source)
    if valid && len(result.errors) != 0 { panic(result.errors[0].message) }
    if !valid && len(result.errors) == 0 { panic("semantic accepted invalid source") }
}
func main() int {
    check("package main\nenum message { count(int), empty, }\nfunc read(message value) int { return switch value { message.count(payload): payload, message.empty: 0, } }", true)
    check("package main\nenum message { count(int), empty, }\nfunc create() message { return message.count(42) }", true)
    check("package main\nenum message { count(int), empty, }\nfunc read(message value) int { return switch value { message.count(payload): payload + true, message.empty: 0, } }", false)
    check("package main\nenum message { count(int), empty, }\nfunc create() message { return message.count(true) }", false)
    check("package main\nenum message { count(int), empty, }\nfunc read(message value) int { return switch value { message.count(): 1, message.empty: 0, } }", false)
    check("package main\nenum parcel[t] { value(t), }\nfunc read(parcel[int] input) int { return switch input { parcel.value(payload): payload, } }", true)
    check("package main\nenum message { count(int), empty, }\nfunc read(message value) int { return switch value { message.count(payload): payload, } }", false)
    check("package main\nenum parcel[t] { value(t), empty, }\nstruct holder { parcel[int] data }\nfunc create() holder { return holder { data: parcel.empty } }", true)
    check("package main\nenum node { value(int), }\nenum tree { leaf(node), }\nfunc read(tree value) int { return switch value { tree.leaf(node.value(payload)): payload, } }", true)
    check("package main\nenum parcel[t] { value(t), }\nfunc (parcel[t] self) get() t { return switch self { parcel.value(payload): payload, } }\nfunc read(parcel[int] input) int { return input.get() }", true)
    check("package main\nenum parcel[t] { value(t), }\nfunc create() parcel[int] { return parcel.value(42) }", true)
    check("package main\nenum message { count(int), empty, }\nfunc read(message input) int { return int(input) }", false)
    check("package main\nenum message { count(int), empty, }\nenum other { count(int), }\nfunc read(message input) int { return switch input { other.count(payload): payload, _: 0, } }", false)
    check("package main\nfunc same[t](t a, t b) t { return a }\nfunc read() int { return same(1, 2) }", true)
    check("package main\nfunc same[t](t a, t b) t { return a }\nfunc read() int { return same(1, true) }", false)
    check("package main\nstruct int_expr { int value }\nenum expr { int(int_expr), }\nfunc read(expr input) int { return switch input { expr.int(payload): payload.value, } }\nfunc create() expr { return expr.int(int_expr { value: 42 }) }", true)
    check("package main\nenum result[t,e] { ok(t), err(e), }\nfunc fail() result[int,string] { return result.err(\"error\") }\nfunc read(result[int,string] input) int { return switch input { result.ok(value): value, result.err(error): 0, } }", true)
    return 42
}
S
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "${sources[@]}" "$work/semantic.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical enum payload constructors and pattern bindings: PASS'
