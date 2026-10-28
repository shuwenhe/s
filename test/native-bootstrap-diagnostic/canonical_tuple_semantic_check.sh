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
needed=['check_source_file','declaration_ref_equal','declaration_ref_display','find_struct_declaration'];selected=set()
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
    check("package main\nfunc source() (int,string) { return 1, \"a\" }\nfunc relay() (int,string) { source() }", true)
    check("package main\nfunc source() (int,string) { return 1, \"a\" }\nfunc relay() (int,string) { return source() }", true)
    check("package main\nfunc relay() (int,string) { (1, \"a\") }", true)
    check("package main\nfunc source() (int,bool) { return 1, true }\nfunc relay() (int,string) { source() }", false)
    check("package main\nfunc source() (int,int,int) { return 1, 2, 3 }\nfunc relay() (int,int) { source() }", false)
    check("package main\nfunc source() (int,int) { return 1, 2 }\nfunc relay() int { source() }", false)
    check("package main\nfunc source[t](t value) (t,t) { return value, value }\nfunc relay[t](t value) (t,t) { source(value) }", true)
    check("package main\nfunc source[t](t value) (t,t) { return value, value }\nfunc relay[t](t value) (t,int) { source(value) }", false)
    check("package main\nfunc source() ((int,string),bool) { return (1, \"a\"), true }\nfunc relay() ((int,string),bool) { source() }", true)
    check("package main\nstruct Cell { int value }\nfunc source() (Cell,int) { return Cell { value: 1 }, 2 }\nfunc relay() (Cell,int) { source() }", true)
    check("package main\nfunc pair() (int,int) { first, second := 1, 2; first, second = second, first; return first, second }", true)
    check("package main\nfunc pair() (int,int) { first, second := 1, true; return first, second }", false)
    check("package main\nfunc pair() int { first, second := 1, 2, 3; return first }", false)
    check("package main\nfunc pair() int { first, first := 1, 2; return first }", false)
    return 42
}
S
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "${sources[@]}" "$work/semantic.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical tuple semantic arity, bindings and element types: PASS'
