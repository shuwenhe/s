#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-dfa-signature.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re,sys
root,work=map(Path,sys.argv[1:])
text=(root/'src/cmd/compile/internal/ir/dfa.s').read_text()
parts=['package probe\nstruct int_set { int[] values }\n']
for name in ['int_set_new','int_set_add','int_set_contains']:
    start=re.search(r'^func '+name+r'\(',text,re.M).start()
    match=re.search(r'^func ',text[start+1:],re.M)
    parts.append(text[start:start+1+match.start()] if match else text[start:])
parts.append('func main() int { return 42 }\n')
(work/'main.s').write_text('\n'.join(parts))
PY
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
printf 'package probe\nfunc invalid(Unknown* input) () {}\nfunc main() int { return 42 }\n' > "$work/invalid.s"
if "$compiler" --compile-unit "$work/invalid.sasm" "$work/invalid.s" > "$work/rejected.log" 2>&1; then
    echo 'unknown reference referent accepted' >&2; exit 1
fi
grep -q 'unproven reference parameter\|unknown\|unsupported' "$work/rejected.log"
echo 'production dataflow signatures and unknown referent rejection: PASS'
