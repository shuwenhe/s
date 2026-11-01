#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-vec-set.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.s" <<'S'
package main
struct item { int amount }
struct holder { item[] items }
func set_unit(item[] values, item replacement) () { return values.set(0, replacement) }
func validate() () {
    first := item { amount: 1 }
    replacement := item { amount: 42 }
    values := [first];
    values.set(0, replacement)
    replacement.amount = 99
    if values[0].amount != 42 { panic("wrong record replacement") }
    set_unit(values, replacement)
    nested := holder { items: values }
    next := item { amount: 20 }
    nested.items.set(0, next)
    if nested.items[0].amount != 20 || values[0].amount != 42 { panic("wrong nested snapshot") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
python3 - "$work" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);lines=(p/'main.ir').read_text().splitlines()
call=next(i for i,line in enumerate(lines) if '|__vec_set|3' in line)
arguments=[i for i in range(call) if lines[i].startswith('ARG|')][-3:]
for name,argument,value in [('index',arguments[1],'"bad"'),('element',arguments[2],'"wrong"'),('receiver',arguments[0],'"missing"')]:
 changed=lines.copy();fields=changed[argument].split('|');fields[1]=value;changed[argument]='|'.join(fields)
 (p/(name+'.ir')).write_text('\n'.join(changed)+'\n')
PY
for name in index element receiver; do
 printf preserve > "$work/output"
 if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$name.ir" "$work/output" > "$work/$name.log" 2>&1; then
    echo "accepted invalid vec_set $name" >&2; exit 1
 fi
 test "$(cat "$work/output")" = preserve
done
echo 'native vector set resolves receiver paths, snapshots records and rejects wrong indices: PASS'
