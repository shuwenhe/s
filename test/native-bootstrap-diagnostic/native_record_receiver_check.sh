#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-record-receiver.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/receiver.s" <<'S'
package main
struct counter { int value }
func (counter* self) add(int amount) { self.value = self.value + amount }
func increment(target* counter) { target.add(1) }
func (counter* self) tick() { increment(self) }
func (counter* self) sum(int a, int b, int c, int d, int e, int f) {
    self.value = a + b + c + d + e + f
}
func (counter* self) number() int { return self.value }
func repeat(counter* target, int count) {
    for i := 0; i < count; i = i + 1 { target.tick() }
}
func descend(target* counter, int count) {
    if count <= 0 { return }
    target.tick()
    next := count - 1
    descend(target, next)
}
func main() int {
    value := counter {}
    value.sum(1, 2, 3, 4, 5, 6)
    repeat(value, 10)
    descend(value, 11)
    return value.number()
}
S
"$root/bin/s_seed" --compile-native-unit "$work/receiver.ir" "$work/receiver.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/receiver.ir" "$work/receiver"
status=0; timeout 15 "$work/receiver" || status=$?
test "$status" -eq 42
cat > "$work/alpha.s" <<'S'
package alpha
struct counter { int value }
func (counter* self) set() { self.value = 40 }
S
cat > "$work/beta.s" <<'S'
package beta
struct counter { int value }
func (counter* self) set() { self.value = 2 }
S
cat > "$work/import.s" <<'S'
package main
import "alpha"
import "beta"
func touch(alpha.counter* target) { target.set() }
func main() int {
    one := alpha.counter {}
    two := beta.counter {}
    touch(one)
    two.set()
    return one.value + two.value
}
S
"$root/bin/s_seed" --compile-native-unit "$work/import.ir" "$work/alpha.s" "$work/beta.s" "$work/import.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/import.ir" "$work/import"
status=0; "$work/import" || status=$?
test "$status" -eq 42
printf 'preserve output\n' > "$work/output"
cp "$work/output" "$work/saved"
python3 - "$work" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
base='package main\nstruct counter { int value }\n'
cases={
 'alias': 'func pair(a* counter, b* counter) {}\nfunc (counter* self) bad() { pair(self, self) }',
 'escape': 'func (counter* self) bad() counter { return self }',
 'copy': 'func (counter* self) bad() { copy := self; copy.value = 1 }',
 'value-call': 'func value(counter v) int { return v.value }\nfunc (counter* self) bad() int { return value(self) }',
 'effects': 'func effect() int { return 1 }\nfunc (counter* self) add(int amount) { self.value = amount }\nfunc (counter* self) bad() { self.add(effect()) }',
 'transitive-escape': 'func leaf(target* counter) counter { return target }\nfunc (counter* self) bad() { leaf(self) }',
}
for name,code in cases.items():
 (p/(name+'.s')).write_text(base+code+'\nfunc main() int { return 42 }\n')
text=(p/'receiver.ir').read_text()
assert 'ARG|self|mutable_borrow|_' in text
(p/'erased.ir').write_text(text.replace('ARG|self|mutable_borrow|_', 'ARG|self|_|_',1))
assert 'ARG|6|_|_' in text
(p/'wrong-scalar.ir').write_text(text.replace('ARG|6|_|_', 'ARG|"bad"|_|_',1))
probe='''NOP|return-transfer:scalar_zero|_|int
FUNC_BEGIN|scalar_zero|_|_
RET|0|_|_
FUNC_END|scalar_zero|_|_
'''
# Even an otherwise valid zero-argument call cannot occur while an outer
# exclusive argument is pending. Its own body and metadata are valid.
(p/'pending.ir').write_text(text.replace('ARG|self|mutable_borrow|_', 'ARG|self|mutable_borrow|_\nCALL|reborrow_probe|scalar_zero|0',1)+probe)
imported=(p/'import.ir').read_text()
assert '|alpha.counter*.set|' in imported
lines=imported.splitlines()
changed=0
for i,line in enumerate(lines):
 if line.startswith('CALL|') and '|alpha.counter*.set|' in line:
  lines[i]=line.replace('|alpha.counter*.set|','|beta.counter*.set|'); changed+=1
assert changed == 1
(p/'wrong-schema.ir').write_text('\n'.join(lines)+'\n')
# Two distinct borrowed parameters must not be collapsed into one actual root.
forged='''package main
struct counter { int value }
func pair(a* counter, b* counter) { a.value = b.value }
func relay(a* counter, b* counter) { pair(a, b) }
func main() int {
    one := counter {}
    two := counter { value: 42 }
    relay(one, two)
    return one.value
}
'''
(p/'pair.s').write_text(forged)
PY
for name in alias escape copy value-call effects transitive-escape; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "invalid receiver borrow accepted: $name" >&2; exit 1
    fi
    grep -Eq 'unproven|unsupported_owner' "$work/$name.log"
    cmp "$work/output" "$work/saved"
done
"$root/bin/s_seed" --compile-native-unit "$work/pair.ir" "$work/pair.s"
python3 - "$work" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=(p/'pair.ir').read_text()
assert 'ARG|a|mutable_borrow|_\nARG|b|mutable_borrow|_' in text
(p/'alias.ir').write_text(text.replace('ARG|a|mutable_borrow|_\nARG|b|mutable_borrow|_', 'ARG|a|mutable_borrow|_\nARG|a|mutable_borrow|_',1))
PY
cat > "$work/forbidden" <<'SH'
#!/bin/sh
printf called >> "$S_TEST_TOOL_LOG"
exit 99
SH
chmod +x "$work/forbidden"
for name in erased alias wrong-schema pending wrong-scalar; do
    if S_SOURCE_ROOT="$root" S_TEST_TOOL_LOG="$work/tools.log" S_BOOTSTRAP_AS="$work/forbidden" S_BOOTSTRAP_LD="$work/forbidden" \
        "$root/bin/s_seed" --emit-standalone-amd64 "$work/$name.ir" "$work/output" > "$work/$name-ir.log" 2>&1; then
        echo "forged reborrow IR accepted: $name" >&2; exit 1
    fi
    grep -Eq 'unproven|unsupported_owner' "$work/$name-ir.log"
    cmp "$work/output" "$work/saved"
done
test ! -e "$work/tools.log"
echo 'native receiver mutation, stack argument, loop/recursive reborrows and escape/alias rejection: PASS'
