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
needed=['check_source_file_for_compile','check_source_file','declaration_ref_equal','declaration_ref_display','find_struct_declaration','check_pattern','instantiate_type','match_type_pattern_ref','qualified_package_part','qualified_decl_part','lookup_name_type','is_unknown','pattern_is_wild'];selected=set()
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
    if valid && len(result.errors) != 0 { eprintln(result.errors[0].code + ": " + result.errors[0].message); panic(result.errors[0].message) }
    if !valid && len(result.errors) == 0 { panic("semantic accepted invalid source") }
}
func main() int {
    check("package main\nfunc read(string unit) string { unit }", true)
    check("package main\nfunc read() int { unit := 42; unit }", true)
    check("package main\nconst unit = 42\nfunc read() int { unit }", true)
    check("package main\nfunc empty(string unit) () { () }", true)
    check("package main\nfunc empty() () { unit }", true)
    check("package main\nfunc wrong(string unit) int { unit }", false)
    check("package main\nfunc read(int unit) string { unit }", false)
    check("package main\nfunc read() int { () }", false)
    check("package main\nfunc read() int { unit := 1; unit := 2; return unit }", false)
    check("package main\nstruct Config { int value }\nselected := create()\nfunc create() Config { return Config { value: 42 } }\nfunc read() Config { return selected }", true)
    check("package main\nenum Code { first, second }\nfunc read(Code value) int { return switch value { Code.first: 42, Code.second: { return 42 }, } }", true)
    check("package main\nenum Code { first, second }\nfunc read(Code value) int { return switch value { Code.first: { return 42 }, Code.second: { return true }, } }", false)
    check("package alpha\nstruct record { int field }\nenum Wrapper { wrap(record), none }\nfunc read(Wrapper value) int { return switch value { Wrapper.wrap(payload): payload.field, Wrapper.none: 0, } }\npackage beta\nstruct record { string field }", true)
    check("package main\nenum Code { first, second }\nfunc read(Code value) int { switch value { Code.first: 42, Code.second: (), }; return 42 }", true)
    check("package main\nenum Code { first, second }\nfunc read(Code value) int { return switch value { Code.first: 42, Code.second: (), } }", false)
    check("package alpha\nstruct token { int line }\npackage beta\nstruct token { int line }\npackage main\nfunc read(token value) int { return value.line }", false)
    check("package main\nenum item { other }\nstruct record { int value }\nfunc read(record item) int { return item.value }", true)
    check("package main\nstruct point { int x }\nfunc pair() (int,point) { return 1, point { x: 2 } }", true)
    check("package main\nfunc read(int value) int { var value = value; return value }", true)
    check("package main\nfunc read() int { var value = 1; var value = 2; return value }", false)
    check("package main\nfunc read(int value) int { var local = value; return local }", true)
    check("package main\nfunc read() int { var := 42; return var }", true)
    check("package main\nfunc update(int[] values) () { values.set(0, 42) }", true)
    check("package main\nfunc update(int[] values) () { values.set(0, true) }", false)
    check("package main\nfunc update(int[] values) () { values.set(false, 42) }", false)
    check("package main\nfunc update(int[] values) () { values.set(0) }", false)
    check("package main\nfunc update(int[] values) () { values.push(42) }", true)
    check("package main\nfunc update(int[] values) () { values.push(true) }", false)
    check("package main\nfunc size(int[] values) int { return values.len() }", true)
    check("package alpha\nstruct token { int line }\nfunc build() token { return token { line: 42 } }\npackage beta\nstruct token { string line }", true)
    check("package alpha\nstruct token { int line }\nstruct box[t] { t value }\nfunc build[token](token value) box[token] { return box[token] { value: value } }", true)
    check("package alpha\nstruct token { int line }\nfunc build() beta.token { return token { line: 42 } }\npackage beta\nstruct token { string line }", false)
    check("package alpha\nenum Flag { first }\npackage beta\nenum Flag { first }\npackage main\nfunc ambiguous(Flag value) bool { return value == beta.Flag.first }", false)
    check("package alpha\nstruct token { int line }\nstruct box[t] { t value }\nfunc read[token](box[token] value) alpha.token { return value.value }", false)
    check("package alpha\nstruct token { int line }\nstruct box[t] { t value }\nfunc read[token](box[token] value) token { return value.value }", true)
    check("package alpha\nstruct token { int line }\nfunc read(token value) int { return value.line }\npackage beta\nstruct token { string line }", true)
    check("package alpha\nstruct token { int line }\nfunc read(token[] values) int { return values[0].line }\npackage beta\nstruct token { string line }", true)
    check("package alpha\nstruct token { int line }\nfunc read(beta.token value) int { return value.line }\npackage beta\nstruct token { string line }", false)
    check("package main\nenum Kind { first, second }\nfunc same(Kind value) bool { return value == Kind.first }", true)
    check("package main\nenum Kind { first }\nenum Other { first }\nfunc same(Kind value) bool { return value == Other.first }", false)
    check("package main\nenum Kind { first }\nfunc same(Kind value) bool { return value == 0 }", false)
    check("package main\nenum Payload { some(int), none }\nfunc same(Payload value) bool { return value == value }", false)
    check("package main\nenum Phantom[T] { none }\nfunc same(Phantom[int] value) bool { return value == value }", false)
    check("package main\nenum Kind { first }\nfunc same(Kind[] values) bool { return values == values }", false)
    check("package alpha\nfunc read() int { return 1 }\npackage beta\nfunc read() int { return 2 }", true)
    check("package alpha\nfunc read() int { return 1 }\nfunc read() int { return 2 }", false)
    check("package main\nextern \"intrinsic\" func __host_char_at(string text, int index) string\nextern \"intrinsic\" func __host_char_at(string source, int offset) string", true)
    check("package main\nextern \"intrinsic\" func __host_char_at(string text, int index) string\nextern \"intrinsic\" func __host_char_at(string source, bool offset) string", false)
    check("package main\nextern \"intrinsic\" func __host_char_at(string text, int index) string\nextern \"other\" func __host_char_at(string source, int offset) string", false)
    check("package main\nextern \"intrinsic\" func __host_char_at(string text, int index) string\nextern \"intrinsic\" func __host_char_at(string source, int offset) int", false)
    check("package main\nconst selected = 1\nfunc read(int value) int { return switch value { selected: 10, 2: 20, _: 0, } }", true)
    check("package main\nconst selected = true\nfunc read(int value) int { return switch value { selected: 10, _: 0, } }", false)
    check("package main\nfunc read(int value) int { return switch value { unknown: unknown + 1, } }", true)
    check("package main\nconst selected = 1\nfunc read(int value) int { return switch value { selected: 10, 1: 20, _: 0, } }", false)
    check("package main\ncounter := 1\nfunc read() int { counter = counter + 1; return counter }", true)
    check("package main\ncounter := 1\nfunc read() int { return main.counter }", true)
    source := "package main\nfunc main() int { return missing(1) }"
    file, failure := compile.internal.syntax.parse_source(source)
    if failure.message != "" { return 1 }
    result := compile.internal.semantic.check_source_file(file, source)
    if len(result.errors) == 0 { return 2 }
    found := false
    i := 0
    for i < len(result.errors) {
        if result.errors[i].code == "e3100" { return 3 }
        if result.errors[i].code == "e1001" {
            found = true
            if result.errors[i].anchor != "missing" { return 4 }
            if result.errors[i].line != 2 { return 5 }
        }
        i = i + 1
    }
    if !found { return 7 }
    valid_file, valid_failure := compile.internal.syntax.parse_source("package main\nfunc main() int { return 0 }")
    clean := compile.internal.semantic.check_source_file(valid_file, "package main\nfunc main() int { return 0 }")
    if len(clean.errors) != 0 { return 6 }
    invalid_source := "package main\nfunc broken() int { return missing_first }\nfunc main() int { return missing_second }"
    invalid_file, invalid_failure := compile.internal.syntax.parse_source(invalid_source)
    if invalid_failure.message != "" { return 8 }
    first_error := compile.internal.semantic.check_source_file_for_compile(invalid_file, invalid_source)
    all_errors := compile.internal.semantic.check_source_file(invalid_file, invalid_source)
    if len(first_error.errors) == 0 || len(all_errors.errors) <= len(first_error.errors) { return 9 }
    accepted := compile.internal.semantic.check_source_file_for_compile(valid_file, "package main\nfunc main() int { return 0 }")
    if len(accepted.errors) != 0 { return 10 }
    return 42
}
S
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "${sources[@]}" "$work/semantic.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical const patterns and original semantic diagnostics: PASS'
