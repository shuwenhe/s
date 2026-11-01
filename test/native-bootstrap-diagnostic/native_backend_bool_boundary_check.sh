#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-backend-bool-boundary.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); work=Path(sys.argv[2])
source=(root/'src/cmd/compile/internal/core/backend.s').read_text()
start=source.index('func bool_from_value(')
end=source.index('\nfunc eval_while_expr(',start)
helper=source[start:end]
(work/'input.s').write_text('''package main
import "std.option"
enum value { bool(bool), int(int), string(string), unit(int), channel(int), fn_ref(string), fn_map(int), owned_box(int) }
'''+helper+'''
func find_binding_index(int[] values) int { return 0 }
func main() int {
    values := [42];
    source_index := find_binding_index(values)
    return values[source_index]
}
''')
PY
"$root/bin/s_seed" --compile-native-unit "$work/program.ir" "$root/src/option/option.s" "$work/input.s"
"$root/bin/s_seed" --dump-ast "$root/src/cmd/compile/internal/core/backend.s" "$work/backend.ast"
grep -Eq '^  FN_STMT .* name=find_binding_index params=2$' "$work/backend.ast"
grep -Eq '^  FN_STMT .* name=eval_while_expr params=5$' "$work/backend.ast"
echo 'production bool helper preserves following function boundaries: PASS'
