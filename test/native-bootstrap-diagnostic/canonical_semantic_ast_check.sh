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
    file, failure := compile.internal.syntax.parse_source(source)
    if failure.message != "" { eprintln(failure.message); panic(failure.message) }
    result := compile.internal.semantic.check_source_file(file, source)
    if valid && len(result.errors) != 0 { eprintln(result.errors[0].message); panic(result.errors[0].message) }
    if !valid && len(result.errors) == 0 { eprintln("semantic accepted invalid source"); panic("semantic accepted invalid source") }
}
func main() int {
    check("package main\nfunc main(int value) int { return value + 1 }", true)
    check("package main\nfunc main(int value) int { value + 1 }", true)
    check("package main\nenum Code { answer = 40, }\nfunc main(int value) int { return int(Code.answer) + value }", true)
    check("package main\nfunc main(int value) int { }", false)
    check("package main\nfunc main(int value) int { return true }", false)
    check("package main\nfunc main(int value) int { return unknown }", false)
    check("package main\nenum Code { answer, answer, }\nfunc main() int { return 42 }", false)
    check("package main\nenum Code { answer, }\nfunc main() int { return Code.answer + 1 }", false)
    check("package model.types\nenum Flag { off, on(bool), }\npackage main\nimport \"model.types\"\nfunc main() int { flag := model.types.Flag.on(true); return switch flag { model.types.Flag.on(v): if v { 42 } else { 0 }, model.types.Flag.off: 0, } }", true)
    check("package model.types\nenum Code { answer = 42, }\npackage main\nimport \"model.types\"\nfunc main() int { return int(model.types.Code.answer) }", true)
    check("package model.types\nenum Flag { off, on(bool), }\npackage main\nimport \"model.types\"\nfunc main() int { flag := model.types.Flag.on(1); return 42 }", false)
    check("package model.types\nenum Code { answer = 42, }\npackage main\nimport \"model.types\"\nfunc main() int { model := 1; return int(model.types.Code.answer) }", false)
    check("package main\nconst first = 40\nconst answer = first + 2\nfunc main() int { return answer }", true)
    check("package main\nconst answer = true + 1\nfunc main() int { return 42 }", false)
    check("package main\nconst answer = 40\nconst answer = 42\nfunc main() int { return answer }", false)
    check("package main\nstruct Counter { int value }\nfunc (Counter* self) positive() bool { return self.value > 0 }\nfunc (Counter* self) negative() bool { return !self.positive() }\nfunc main() int { counter := Counter { value: 42 }; if counter.negative() { return 1 }; return 42 }", true)
    check("package main\nstruct Counter { int value }\nfunc (&Counter self) positive() bool { return self.value > 0 }\nfunc read(&Counter counter) bool { return counter.positive() }\nfunc main() int { return 42 }", true)
    check("package main\nstruct Counter { int value }\nfunc (Counter* self) positive() bool { return self.value > 0 }\nfunc read(&Counter counter) bool { return counter.positive() }\nfunc main() int { return 42 }", false)
    check("package main\nstruct Counter { int value }\nfunc (Counter* self) positive() bool { return self.value > 0 }\nfunc create() Counter { return Counter { value: 42 } }\nfunc main() int { if create().positive() { return 42 }; return 1 }", false)
    return 42
}
S
python3 - "$root" "$work" <<'PY2'
from pathlib import Path
import json,sys
root,work=map(Path,sys.argv[1:])
source='package main\nimport "std.result"\nfunc main() int { return 42 }\nfunc accepts(result[int,string] input) bool { return input.is_err() }\n'+(root/'src/result/result.s').read_text()
# Long literals exceed the seed IR operand limit; assemble the source at runtime.
chunks=[json.dumps(source[i:i+256]) for i in range(0,len(source),256)]
p=work/'main.s';text=p.read_text();text=text.replace('    return 42\n}\n','    check('+ ' + '.join(chunks)+', true)\n    return 42\n}\n');p.write_text(text)
PY2
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"${S_TEST_SEED:-$root/bin/s_seed}" --compile-native-unit "$work/main.ir" "${sources[@]}" "$work/semantic.s" "$work/main.s"
S_SOURCE_ROOT="$root" "${S_TEST_SEED:-$root/bin/s_seed}" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical parser and semantic AST checks execute natively with positive and negative cases: PASS'
