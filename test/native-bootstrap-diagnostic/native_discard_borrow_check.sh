#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-discard.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "discard test artifacts: $work" >&2; fi' EXIT
cat > "$work/discard.s" <<'S'
package main
struct value { int number; string name; int[] items }
calls := 0
func build(int number) value {
    calls = calls + number
    return value { number: number, name: "owned", items: [1, 2] }
}
func discard(int number) () { _ := build(number) }
func flow(target* value, int count) {
    local := build(0)
    _ := local
    local.number = 7
    if local.number != 7 { target.number = -100; return }
    for i := 0; i < count; i = i + 1 {
        if i == 1 { _ := build(0); continue }
        _ := build(0)
        target.number = target.number + 1
    }
    if target.number == 2 { _ := 7 } else { _ := "unused" }
    _ := ()
    _ := target.number
    _ := target.name
    _ := target.items
}
func main() int {
    discard(20)
    discard(22)
    owner := value { number: 0, name: "owner", items: [7] }
    flow(owner, 3)
    if owner.number != 2 || owner.name != "owner" || owner.items[0] != 7 { return 1 }
    return calls
}
S
"$root/bin/s_seed" --compile-native-unit "$work/discard.ir" "$work/discard.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/discard.ir" "$work/discard"
status=0; "$work/discard" || status=$?
test "$status" -eq 42
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/discard"
echo 'native discarded record results preserve callee effects: PASS'

python3 - "$work" <<'PY_FORGED'
from pathlib import Path
import re,sys
w=Path(sys.argv[1]); text=(w/'discard.ir').read_text()
start=text.index('FUNC_BEGIN|discard|'); end=text.index('FUNC_END|discard|',start)
body=text[start:end]
(w/'unknown.ir').write_text(text[:start]+re.sub(r'MOV\|_\|[^|]+\|_', 'MOV|_|undefined_value|_',body,count=1)+text[end:])
(w/'read-sink.ir').write_text(text[:start]+body.replace('UNIT|','MOV|read_discard|_|_\nUNIT|',1)+text[end:])
start=text.index('FUNC_BEGIN|build|'); end=text.index('FUNC_END|build|',start)
body=text[start:end]
(w/'bad-return.ir').write_text(text[:start]+re.sub(r'RET\|[^|]+\|_\|_', 'RET|0|_|_',body,count=1)+text[end:])
(w/'resource.ir').write_text(text.replace('NOP|record-field:main.value|number|int\n','NOP|record-field:main.value|number|int*\n'))
lines=text.splitlines(); start=next(i for i,l in enumerate(lines) if l.startswith('FUNC_BEGIN|flow|'))+1
while lines[start].startswith('PARAM|'): start+=1
for name,source in [('borrowed','target'),('unknown-unreachable','undefined_value'),('borrowed-unreachable','target')]:
    changed=lines[:]
    payload=['MOV|_|'+source+'|_']
    if name.endswith('unreachable'): payload=['JUMP|discard_after_unreachable|_|_']+payload+['LABEL|discard_after_unreachable|_|_']
    changed[start:start]=payload
    (w/(name+'.ir')).write_text('\n'.join(changed)+'\n')
PY_FORGED
cat > "$work/forbidden-tool" <<'TOOL'
#!/bin/sh
echo invoked >> "$S_DISCARD_TOOL_LOG"
exit 99
TOOL
chmod +x "$work/forbidden-tool"
printf 'preserve destination\n' > "$work/output"
cp "$work/output" "$work/saved"
for bad in unknown read-sink bad-return resource borrowed unknown-unreachable borrowed-unreachable; do
    if S_DISCARD_TOOL_LOG="$work/tools.log" S_BOOTSTRAP_AS="$work/forbidden-tool" S_BOOTSTRAP_LD="$work/forbidden-tool" \
        S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$bad.ir" "$work/output" > "$work/$bad.log" 2>&1; then
        echo "invalid discard IR accepted: $bad" >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
    if [ -e "$work/tools.log" ]; then
        echo "invalid discard reached native tools: $bad" >&2; exit 1
    fi
done
echo 'discard CFG/owner preservation and unknown/borrowed/resource/callee rejection: PASS'
