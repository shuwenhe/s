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
text=text.replace('func collect_consts(source_file file, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics) const_binding[] {', 'func collect_consts(source_file file, function_binding[] functions, trait_binding[] traits, string source, semantic_error[] diagnostics) const_binding[] {\n    eprintln("entered collect_consts")')
for label,statement in [
 ('enum declarations','diagnostics := canonical_enum_errors(file)'),
 ('functions','functions := collect_functions(file)'),
 ('traits','traits := collect_traits(file)'),
 ('constants','consts := collect_consts(file, functions, traits, source, diagnostics)'),
 ('structs','structs := collect_structs(file)'),
 ('identities','declarations := establish_declaration_identities(functions, traits, consts, structs)'),
 ('globals','globals := canonical_collect_globals(file, functions, traits, consts, declarations, source, diagnostics)'),
 ('function set','function_errors := validate_function_set(functions, source, diagnostics)')]:
 text=text.replace(statement,'eprintln("semantic phase: '+label+'")\n    '+statement)
text=text.replace('checked := check_item(file.items[i]', 'if i % 100 == 0 { eprintln("checked item=" + std.prelude.to_string(i)) }\n        checked := check_item(file.items[i]')
(work/'semantic.s').write_text(text)
PY
python3 - "$root" "$work/full.s" <<'PY_SOURCE'
from pathlib import Path
import sys
root=Path(sys.argv[1])
paths=(root/'.bootstrap/native-imports/stage1.sources').read_text().splitlines()
Path(sys.argv[2]).write_text('\n'.join((root/p).read_text() for p in paths))
PY_SOURCE
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.semantic"; "std.fs"; "compile.internal.ast")
func main() int {
    args := host_args()
    text := std.fs.read_to_string(args[1])
    if text.is_err() { return 2 }
    source := text.unwrap()
    file := compile.internal.ast.source_file { pkg: "" }
    if len(args) > 2 {
        manifest_result := std.fs.read_to_string(args[2])
        manifest := manifest_result.unwrap()
        paths := string[]()
        path := ""
        p := 0
        for p < len(manifest) {
            ch := string(manifest[p])
            if ch == "\n" { if path != "" { paths = append(paths, path); path = "" } }
            else { path = path + ch }
            p = p + 1
        }
        if path != "" { paths = append(paths, path) }
        p = 0
        for p < len(paths) {
            input_result := std.fs.read_to_string(args[3] + "/" + paths[p])
            input := input_result.unwrap()
            part, failure := compile.internal.syntax.parse_source(input)
            if failure.message != "" { eprintln(paths[p] + ": " + failure.message); return 3 }
            if file.pkg == "" { file.pkg = part.pkg }
            i := 0
            for i < len(part.items) {
                file.items.push(part.items[i])
                file.item_packages.push(part.item_packages[i])
                i = i + 1
            }
            i = 0
            for i < len(part.uses) { file.uses.push(part.uses[i]); i = i + 1 }
            p = p + 1
            if p % 25 == 0 { eprintln("merged files=" + std.prelude.to_string(p)) }
        }
    } else {
        parsed, failure := compile.internal.syntax.parse_source(source)
        if failure.message != "" { eprintln("parser: " + failure.message + " line=" + std.prelude.to_string(failure.line)); return 3 }
        file = parsed
    }
    eprintln("parsed items=" + std.prelude.to_string(len(file.items)))
    result := compile.internal.semantic.check_source_file(file, source)
    eprintln("semantic diagnostics=" + std.prelude.to_string(len(result.errors)))
    i := 0
    for i < len(result.errors) && i < 40 {
        diagnostic := result.errors[i]
        eprintln(diagnostic.code + " line=" + std.prelude.to_string(diagnostic.line) + " anchor=" + diagnostic.anchor + " " + diagnostic.message)
        i = i + 1
    }
    if len(result.errors) != 0 { return 1 }
    return 0
}
S
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s src/cmd/compile/internal/prelude.s src/cmd/compile/internal/typesys/typesys.s src/cmd/compile/internal/typesys/canonical_type.s src/cmd/compile/internal/semantic/canonical_enum.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "${sources[@]}" "$work/semantic.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
probe_args=("$work/full.s")
if [ "${S_SEMANTIC_PROBE_PER_FILE:-0}" = 1 ]; then probe_args+=("$root/.bootstrap/native-imports/stage1.sources" "$root"); fi
status=0; (ulimit -v 1572864; ulimit -t 180; /usr/bin/time -v timeout 180 "$work/main" "${probe_args[@]}") || status=$?
if [ "$status" -ne 0 ]; then exit "$status"; fi
echo 'full264 canonical semantic probe: PASS'
