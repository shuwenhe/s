#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-schedule-id.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:]);base=root/'src/cmd/compile/internal/ssa'
def declaration(name):
 s=(base/name).read_text();return s[s.index('struct '):s.index('\nfunc ')]+'\n'
(work/'types.s').write_text('package compile.internal\n'+''.join(declaration(n) for n in ['value.s','block.s','func.s']))
PY
cat > "$work/main.s" <<'S'
package main
import "compile.internal"
func measure(int[] ids) int {
    block := compile.internal.ssa_bb { id: 0, kind: "plain", values: ids, preds: int[](), succs: int[](), control: 0 }
    function := compile.internal.ssa_func { name: "fixture", entry: 0, blocks: [block], values: compile.internal.ssa_value[](), next_block_id: 1, next_value_id: 3 }
    return compile.internal.run_schedule(function)
}
func validate() () {
    if measure([2, 0, 1]) != 2 { panic("wrong schedule changes") }
    if measure([0, 1, 2]) != 0 || measure(int[]()) != 0 { panic("changed ordered IDs") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/types.s" "$root/src/cmd/compile/internal/ssa/schedule.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'native scheduler compares concrete value IDs and reports actual swaps: PASS'
