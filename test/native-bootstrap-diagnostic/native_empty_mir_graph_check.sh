#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-empty-mir.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:]);base=root/'src/cmd/compile/internal'
s=(base/'ir/lower.s').read_text();mir=(base/'mir/mir.s').read_text()
(work/'mir.s').write_text('package compile.internal.mir\nimport "std.option"\n'+mir[mir.index('enum mir_projection_kind {'):mir.index('struct mir_point {')])
def function(name):
 a=s.index('func '+name+'(');b=s.find('\nfunc ',a+1);return s[a:b if b>=0 else len(s)]+'\n'
a=s.index('    if fd.body.is_none() {',s.index('func lower_function_to_mir('));b=s.index('\n    return lower_block_to_mir(',a)
body=s[s.index('\n',a)+1:b].rstrip();assert body.endswith('}')
body=body[:-1].replace('fd.sig.name','function_name')
(work/'lower.s').write_text('package main\nimport ("std.option"; "compile.internal.mir")\n'+function('ir_make_block')+function('make_block_with_condition')+'\nfunc empty_graph(string function_name) mir_graph {\n'+body+'\n}\n')
PY
cat > "$work/main.s" <<'S'
package main
func validate() () {
    graph := empty_graph("declaration")
    if graph.function_name != "declaration" || len(graph.trace) != 0 || len(graph.locals) != 0 { panic("wrong empty graph") }
    if len(graph.blocks) != 1 || graph.blocks[0].label != "entry" { panic("missing entry block") }
    if graph.blocks[0].terminator.kind != "return" || graph.blocks[0].terminator.condition.is_some() { panic("wrong empty return") }
    if !graph.borrow_ok || graph.borrow_errors != 0 { panic("wrong borrow result") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$work/mir.s" "$work/lower.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'production empty MIR graph preserves trace, block, terminator and borrow fields: PASS'
