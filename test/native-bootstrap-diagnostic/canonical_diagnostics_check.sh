#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-diagnostics.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re,sys
root,work=map(Path,sys.argv[1:])
s=(root/'src/cmd/compile/internal/semantic/semantic.s').read_text()
positions=list(re.finditer(r'^func ([A-Za-z_][A-Za-z_0-9]*)\(',s,re.M))
functions={m[1]:s[m.start():positions[i+1].start() if i+1<len(positions) else len(s)] for i,m in enumerate(positions)}
needed=['finalize_diagnostics'];selected=set()
while needed:
 name=needed.pop()
 if name in selected or name not in functions:continue
 selected.add(name)
 code=re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',' ',functions[name])
 needed+=re.findall(r'\b([A-Za-z_][A-Za-z_0-9]*)\s*\(',code)
struct=s[s.index('struct semantic_error {'):s.index('\nenum declaration_kind')]
fixture='''
func main() int {
    first := semantic_error { code: "e1", message: "first", severity: "error", tier: 1, line: 2, column: 1, repeat_count: 1 }
    second := semantic_error { code: "e2", message: "second", severity: "error", tier: 1, line: 1, column: 1, repeat_count: 1 }
    errors := finalize_diagnostics([first, second, first])
    if len(errors) != 2 { return 10 }
    if errors[0].code != "e2" || errors[1].code != "e1" || errors[1].repeat_count != 2 { return 11 }
    return 42
}
'''
(work/'main.s').write_text('package main\nimport "std.prelude"\n'+struct+''.join(functions[m[1]] for m in positions if m[1] in selected)+fixture)
PY
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/prelude/prelude.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical diagnostics retain, order and deduplicate real errors: PASS'
