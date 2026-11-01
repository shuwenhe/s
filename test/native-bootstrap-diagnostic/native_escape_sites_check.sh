#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-escape-sites.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:]);s=(root/'src/cmd/compile/internal/mir/mir.s').read_text()
constants=(root/'src/cmd/compile/internal/escape/call.s').read_text()
(work/'constants.s').write_text('package compile.internal.escape\n'+constants[constants.index('const escape_none'):constants.index('func classify_call_escape(')])
(work/'mir.s').write_text('package compile.internal.mir\nimport "std.option"\n'+s[s.index('enum mir_projection_kind {'):s.index('struct mir_point {')])
PY
cat > "$work/main.s" <<'S'
package main
import ("compile.internal.mir"; "compile.internal.escape"; "std.option")
func measure(mir_statement[] statements) int {
    block := mir_basic_block { id: 0, label: "entry", statements: statements, terminator: mir_terminator { kind: "return", condition: option.none, edges: mir_control_edge[]() } }
    graph := mir_graph { function_name: "fixture", blocks: [block], locals: mir_local_slot[](), trace: string[](), entry: 0, exit: 0, borrow_ok: true, borrow_errors: 0, borrow_message: "" }
    return compile.internal.escape.estimate_escape_sites_graph(graph)
}
func validate() () {
    boxed := mir_statement.eval(mir_eval_stmt { op: "box", args: string[]() })
    made := mir_statement.assign(mir_assign_stmt { target: 0, op: "make", args: string[]() })
    allocated := mir_statement.eval(mir_eval_stmt { op: "new", args: string[]() })
    scalar := mir_statement.assign(mir_assign_stmt { target: 1, op: "add", args: string[]() })
    if measure([boxed, made, allocated, scalar]) != 3 { panic("allocation sites lost") }
    if measure([scalar]) != 0 || measure(mir_statement[]()) != 0 { panic("scalar escaped") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$work/mir.s" "$root/src/cmd/compile/internal/escape/expr.s" "$work/constants.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'native escape-site estimator inspects MIR allocations and excludes scalar operations: PASS'
