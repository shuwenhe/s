#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-place-signature.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re, sys
root, work = map(Path, sys.argv[1:])
source = (root/'src/cmd/compile/internal/mir/mir.s').read_text()
names = ['mir_projection_kind', 'mir_place_projection', 'mir_place', 'mir_compare_places', 'mir_check_prefix']
output = 'package compile.internal.mir\n'
for name in names:
    match = re.search(r'^(?:struct|enum|func) '+name+r'\b', source, re.M)
    begin = source.index('{', match.start()); end = source.index('\n}', begin)+2
    output += source[match.start():end]+'\n'
output += '''func main() int {
    place := mir_place { root: "value", projections: mir_place_projection[]() }
    if mir_compare_places(place, "value") { return 1 }
    if mir_check_prefix(place, "value") { return 2 }
    return 42
}
'''
(work/'main.s').write_text(output)
PY
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'canonical MIR place helper signatures accept actual place records and strings: PASS'
