#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-borrow-report.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:]);s=(root/'src/cmd/compile/internal/ownership/borrow.s').read_text()
def function(name):
 a=s.index('func '+name+'(');b=s.find('\nfunc ',a+1);return s[a:b if b>=0 else len(s)]+'\n'
mir=(root/'src/cmd/compile/internal/mir/mir.s').read_text()
a=mir.index('func lower_function(');b=mir.index('\nfunc ',a+1)
line=next(line.strip() for line in mir[a:b].splitlines() if line.strip().startswith('return '))
line=line.replace('function.sig.name','scope').replace('dump_graph(graph)','body')
(work/'report.s').write_text('package main\nimport "compile.internal.borrow"\nfunc production_report(string scope, string body) string { '+line+' }\n')
(work/'borrow.s').write_text('package compile.internal.borrow\n'+''.join(function(n) for n in ['analyze_trace','analyze_function','make_plan_trace','ownership_join_text','ownership_starts_with']))
PY
cat > "$work/main.s" <<'S'
package main
import "compile.internal.borrow"
func validate() () {
    if production_report("scope", "typed MIR") != "borrow scope | typed MIR | plan <empty>" { panic("wrong production reporter") }
    report := compile.internal.borrow.analyze_function("fixture", ["int", "&mut item"], "bb0:return")
    if report != "borrow fixture | bb0:return | plan drop:int, copy:&mut item" { panic("lost borrow report") }
    empty := compile.internal.borrow.analyze_function("bare", string[](), "body")
    if empty != "borrow bare | body | plan <empty>" { panic("lost empty plan report") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/borrow.s" "$work/report.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'native S borrow report preserves scope, MIR body and concrete ownership plan: PASS'
