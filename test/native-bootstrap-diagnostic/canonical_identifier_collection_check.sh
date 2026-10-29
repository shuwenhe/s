#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-identifier-collection.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re,sys
root,work=map(Path,sys.argv[1:]);s=(root/'src/cmd/compile/internal/stage5_gate.s').read_text()
positions=list(re.finditer(r'^func (\w+)\(',s,re.M));functions={m[1]:s[m.start():positions[i+1].start() if i+1<len(positions) else len(s)] for i,m in enumerate(positions)}
needed=['collect_all_identifiers_from_items'];selected=set()
while needed:
 name=needed.pop()
 if name in selected or name not in functions:continue
 selected.add(name);code=re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',' ',functions[name]);needed+=re.findall(r'\b(\w+)\s*\(',code)
record=re.search(r'^struct identifier_info \{[\s\S]*?^\}',s,re.M)[0]
(work/'helpers.s').write_text('package compile.internal.semantic\nimport ("compile.internal.ast"; "std.option"; "std.prelude")\n'+record+'\n'+''.join(functions[m[1]] for m in positions if m[1] in selected))
PY
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.syntax"; "compile.internal.semantic")
func main() int {
    source := "package main\nstruct Box { int value }\nfunc main() int { items[index] = source; first, second = left, right; box := Box { value: record_value }; return 0 }"
    parsed, failure := compile.internal.syntax.parse_source(source)
    if failure.message != "" { return 1 }
    identifiers := compile.internal.semantic.collect_all_identifiers_from_items(parsed.items)
    expected := string[]{"items", "index", "source", "first", "second", "left", "right", "record_value"};
    i := 0
    for i < len(expected) {
        found := false
        j := 0
        for j < len(identifiers) {
            if identifiers[j].identifier_text == expected[i] { found = true }
            j = j + 1
        }
        if !found { return i + 2 }
        i = i + 1
    }
    return 42
}
S
sources=(src/option/option.s src/result/result.s src/prelude/prelude.s src/fs/fs.s src/cmd/compile/internal/ast/ast.s src/cmd/compile/internal/parser/syntax/syntax.s src/cmd/compile/internal/parser/syntax/canonical_parser.s)
for i in "${!sources[@]}"; do sources[$i]="$root/${sources[$i]}"; done
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "${sources[@]}" "$work/helpers.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
status=0; timeout 20 "$work/main" || status=$?
test "$status" -eq 42
echo 'identifier collection: actual visitor traverses stores, parallel targets, tuple operands and record fields: PASS'
