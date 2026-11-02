#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-pass-function-schema.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package compile.internal
extern "intrinsic" func __host_slice(string source, int start, int end) string
func prelude_slice(string source, int start, int end) string { return __host_slice(source, start, end) }
func main() int {
    first := compile.internal.ir.ast.func_decl_ir { name: "first" }
    second := compile.internal.ir.ast.func_decl_ir { name: "second" }
    functions := [first, second];
    sliced := slice_funcs(functions)
    walked := walk_funcs(functions)
    rewritten := rewrite_result_funcs(functions)
    if sliced.functions_seen != 2 || walked.functions_seen != 2 || rewritten.functions_seen != 2 { return 1 }
    return 42
}
// The pass APIs only count and forward opaque functions; their contract needs
// the declaration's identity, with no dependency on unrelated AST contents.
package compile.internal.ir.ast
struct func_decl_ir { string name }
S
python3 - "$root" "$work" <<'PYTEST'
from pathlib import Path
import re, sys
root, work = map(Path, sys.argv[1:])
source = (root / 'src/cmd/compile/internal/walk/walk.s').read_text()
names = {'walk_ir_func', 'walk_funcs', 'new_walk_state', 'analyze_pre_walk',
         'order_func', 'walk_stmt_list', 'calc_decl_sizes', 'empty_walk_stats',
         'merge_walk_stats'}
positions = list(re.finditer(r'^func (\w+)\(', source, re.M))
selected = source[:positions[0].start()]
for i, match in enumerate(positions):
    if match[1] in names:
        selected += source[match.start():positions[i+1].start() if i+1 < len(positions) else len(source)]
(work / 'walk.s').write_text(selected)
PYTEST
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s" \
    "$root/src/cmd/compile/internal/slice/slice.s" \
    "$work/walk.s" \
    "$root/src/cmd/compile/internal/rewriteresults/rewriteresults.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical pass function APIs use a declared IR function schema: PASS'
