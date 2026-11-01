#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-field-reborrow.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/field.s" <<'S'
package main
extern "intrinsic" func __host_read_source(string path) string
struct token { int value }
struct lexer { int position }
struct parser { lexer lex; token current; token next }
func advance(lex* lexer) token {
    lex.position = lex.position + 1
    return token { value: lex.position }
}
func step(p* parser) {
    p.current = p.next
    p.next = advance(p.lex*)
}
func check(parser p) int {
    if p.current.value != 40 { return 1 }
    if p.next.value != 41 { return 2 }
    return p.lex.position + 1
}
func main() int {
    p := parser { lex: lexer { position: 39 } }
    args := host_args()
    message := __host_read_source(args[1])
    eprintln(message)
    step(p)
    step(p)
    checked := check(p)
    last := advance(p.lex*)
    return checked + last.value - 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/field.ir" "$work/field.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/field.ir" "$work/field"
printf 'before field borrow' > "$work/message"
status=0; timeout 15 "$work/field" "$work/message" 2> "$work/stderr" || status=$?
test "$status" -eq 42
grep -qx 'before field borrow' "$work/stderr"
printf 'preserve output\n' > "$work/output"
cp "$work/output" "$work/saved"
python3 - "$work" <<'PY'
from pathlib import Path
import sys
w=Path(sys.argv[1])
base='''package main
struct child { int value }
struct parent { child nested }
func pair(a* parent, b* child) {}
func two(a* child, b* child) {}
func child_only(a* child) {}
'''
cases={
 'parent-alias':'func bad(p* parent) { pair(p, p.nested*) }',
 'field-alias':'func bad(p* parent) { two(p.nested*, p.nested*) }',
 'wrong-type':'func bad(p* parent) { child_only(p*) }',
 'escape':'func bad(p* parent) child { return p.nested*; }',
 'copy-handle':'func bad(p* parent) { alias := p.nested*; }',
}
for name,body in cases.items():
 (w/(name+'.s')).write_text(base+body+'\nfunc main() int { return 42 }\n')
ir=(w/'field.ir').read_text()
assert 'ARG|p.lex|mutable_borrow|_' in ir
(w/'erased.ir').write_text(ir.replace('ARG|p.lex|mutable_borrow|_', 'ARG|p.lex|_|_'))
(w/'wrong-field.ir').write_text(ir.replace('ARG|p.lex|mutable_borrow|_', 'ARG|p.next|mutable_borrow|_'))
(w/'wrong-owner.ir').write_text(ir.replace('ARG|p|mutable_borrow|_', 'ARG|42.lex|mutable_borrow|_'))
lines=ir.splitlines()
for i,line in enumerate(lines):
 if line.startswith('CALL|') and '|__host_read_source|' in line:
  assert lines[i-1].startswith('ARG|')
  lines[i-1]='ARG|42|_|_'
  break
else: raise AssertionError('missing read-source call')
(w/'wrong-io.ir').write_text('\n'.join(lines)+'\n')
(w/'pending-io.ir').write_text(ir.replace('ARG|p.lex|mutable_borrow|_',
 'ARG|p.lex|mutable_borrow|_\nCALL|pending_probe|host_args|0',1))
extra='''NOP|param-transfer:overlap|a|parser*
NOP|borrow-param:overlap|a|main.parser
NOP|param-transfer:overlap|b|lexer*
NOP|borrow-param:overlap|b|main.lexer
NOP|return-transfer:overlap|_|()
FUNC_BEGIN|overlap|_|_
PARAM|a|mutable_borrow|_
PARAM|b|mutable_borrow|_
RET|_|_|_
FUNC_END|overlap|_|_
'''
(w/'overlap.ir').write_text(ir.replace('ARG|p.lex|mutable_borrow|_\n',
 'ARG|p|mutable_borrow|_\nARG|p.lex|mutable_borrow|_\n').replace('|advance|1','|overlap|2')+extra)
PY
for name in parent-alias field-alias wrong-type escape copy-handle; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "invalid field borrow accepted: $name" >&2; exit 1
    fi
    grep -Eq 'unproven|unsupported_owner' "$work/$name.log"
    cmp "$work/output" "$work/saved"
done
cat > "$work/forbidden" <<'SH'
#!/bin/sh
printf called >> "$S_TEST_TOOL_LOG"
exit 99
SH
chmod +x "$work/forbidden"
for name in erased wrong-field wrong-owner overlap wrong-io pending-io; do
    if S_SOURCE_ROOT="$root" S_TEST_TOOL_LOG="$work/tools.log" \
        S_BOOTSTRAP_AS="$work/forbidden" S_BOOTSTRAP_LD="$work/forbidden" \
        "$root/bin/s_seed" --emit-standalone-amd64 "$work/$name.ir" "$work/output" > "$work/$name.log" 2>&1; then
        echo "forged field borrow accepted: $name" >&2; exit 1
    fi
    grep -Eq 'unproven|unsupported_owner' "$work/$name.log"
    cmp "$work/output" "$work/saved"
done
test ! -e "$work/tools.log"
echo 'native field reborrow mutation, snapshots and source/IR rejection: PASS'
