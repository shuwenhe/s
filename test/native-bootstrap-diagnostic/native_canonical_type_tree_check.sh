#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-type-tree.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "canonical tree artifacts: $work" >&2; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); work=Path(sys.argv[2]); base=root/'src/cmd/compile/internal'
source=(base/'typesys/canonical_type.s').read_text()
(work/'canonical.s').write_text(source[:source.index('func construct_canonical_from_string(')])
semantic=(base/'semantic/semantic.s').read_text()
def section(start,end): return semantic[semantic.index(start):semantic.index(end,semantic.index(start)+1)]
def function(name):
    start=semantic.index('func '+name+'('); end=semantic.index('\nfunc ',start+1)
    return semantic[start:end]
(work/'semantic.s').write_text('package compile.internal.semantic\n'+section('enum declaration_kind {','struct struct_binding {')+section('struct declaration_ref {','struct semantic_result {')+function('declaration_ref_equal')+'\n'+function('declaration_ref_display'))
(work/'main.s').write_text('''package main
use compile.internal.canonical_type as ct
func main() int {
    explicit := compile.internal.canonical_type.pointer(ct.primitive("int"))
    if explicit.child[0].primitive_name != "int" { return 5 }
    integer := ct.primitive("int")
    boolean := ct.primitive("bool")
    pointer := ct.pointer(integer)
    nested := ct.pointer(pointer)
    if ct.canonical_type_to_string(nested) != "**int" { return 1 }
    if !ct.canonical_same_type(pointer, ct.pointer(integer)) { return 2 }
    if ct.canonical_same_type(pointer, ct.pointer(boolean)) { return 3 }
    integer.primitive_name = "bool"
    if ct.canonical_type_to_string(pointer) != "*int" { return 4 }
    return 42
}
''')
PY
"$root/bin/s_seed" --compile-native-unit "$work/tree.ir" "$root/src/option/option.s" "$work/semantic.s" "$work/canonical.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/tree.ir" "$work/tree"
status=0; timeout 15 "$work/tree" || status=$?; test "$status" -eq 42
echo 'production canonical type trees preserve equality, rendering and snapshots: PASS'
