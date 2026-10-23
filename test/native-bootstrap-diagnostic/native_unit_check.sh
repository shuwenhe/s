#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-unit.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "unit artifacts: $work" >&2; fi' EXIT
cat > "$work/unit.s" <<'S'
package main
import "std.result"
struct failure { string message }
struct marker { () value }
func id[t](t value) t { return value }
func accept(() value) () { return value }
func default_unit() () {}
func good() ((), failure) { return result.ok(()) }
func bad() ((), failure) { return result.err(failure { message: "ok" }) }
func touch(marker* target, () value) () { target.value = value; return target.value }
func main() int {
    local := id(())
    boxed := box(local)
    holder := marker {}
    argument := accept(boxed.value)
    changed := touch(holder, argument)
    checked := accept(changed)
    empty := accept(default_unit())
    success, no_error := good()
    failed, error := bad()
    accepted := accept(success)
    also_accepted := accept(failed)
    return 40 + len(error.message) + len(no_error.message)
}
S
"$root/bin/s_seed" --compile-native-unit "$work/unit.ir" "$root/src/prelude/prelude.s" "$root/src/result/result.s" "$work/unit.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/unit.ir" "$work/unit"
status=0; timeout 15 "$work/unit" || status=$?
test "$status" -eq 42
# The same typed IR must retain unit through the hosted boundary as well.
python3 - "$work" <<'PYHOST'
from pathlib import Path
import sys
p=Path(sys.argv[1]);text=(p/'unit.s').read_text()
text='\n'.join(line for line in text.splitlines() if not line.startswith('func touch('))+'\n'
text=text.replace('changed := touch(holder, argument)','changed := holder.value')
(p/'hosted.s').write_text(text)
PYHOST
"$root/bin/s_seed" --compile-native-unit "$work/hosted.ir" "$root/src/prelude/prelude.s" "$root/src/result/result.s" "$work/hosted.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-bin "$work/hosted.ir" "$work/hosted"
status=0; timeout 15 "$work/hosted" || status=$?
test "$status" -eq 42
printf 'preserve output\n' > "$work/output"
cp "$work/output" "$work/saved"
python3 - "$work" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
cases={
 'unit_to_int': 'func consume(int value) int { return value }\nfunc main() int { return consume(()) }',
 'int_to_unit': 'func consume(() value) int { return 42 }\nfunc main() int { return consume(0) }',
 'arithmetic': 'func main() int { return () + 1 }',
 'condition': 'func main() int { if () { return 42 }; return 0 }',
 'missing_arg': 'func consume(() value) int { return 42 }\nfunc main() int { return consume() }',
 'extra_arg': 'func consume() int { return 42 }\nfunc main() int { return consume(()) }',
 'missing_expr': 'func main() int { value := ; return 42 }',
 'unit_return_int': 'func wrong() int { return () }\nfunc main() int { return 42 }',
 'int_return_unit': 'func wrong() () { return 0 }\nfunc main() int { return 42 }',
}
for name,body in cases.items(): (p/(name+'.s')).write_text('package main\n'+body+'\n')
PY
for name in unit_to_int int_to_unit arithmetic condition missing_arg extra_arg missing_expr unit_return_int int_return_unit; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "invalid unit program accepted: $name" >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
done
# Replacing a unit value with integer zero must fail independent IR validation.
python3 - "$work" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);text=(p/'unit.ir').read_text();lines=text.splitlines();changed=False
for i,line in enumerate(lines):
 if line.startswith('UNIT|'):
  fields=line.split('|'); lines[i]='MOV|'+fields[1]+'|0|_';changed=True
assert changed, 'unit values have no explicit native IR representation'
(p/'integer-for-unit.ir').write_text('\n'.join(lines)+'\n')
PY
if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/integer-for-unit.ir" "$work/output" > "$work/forged.log" 2>&1; then
    echo 'integer zero accepted as a native unit value' >&2; exit 1
fi
cmp "$work/output" "$work/saved"
echo 'unit literal, generic/result payloads, defaults, ABI and type rejection: PASS'
cat > "$work/array.s" <<'S'
package main
func same(unit value) unit { return value }
func empty() unit {}
func main() int {
    () canonical = ()
    unit alias = canonical
    values := unit[]()
    values.push(())
    values[0] = same(empty())
    value := values[0]
    if value == () { return 42 }
    return 1
}
S
"$root/bin/s_seed" --compile-native-unit "$work/array.ir" "$work/array.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/array.ir" "$work/array"
status=0; timeout 15 "$work/array" || status=$?
test "$status" -eq 42
echo 'unit aliases, arrays, stores, default returns and equality: PASS'
# Independently supplied typed IR must initialize every unit array slot to unit.
cat > "$work/make-unit.ir" <<'IR'
SSEED-TARGET-V1
NOP|return-transfer:main|_|int
FUNC_BEGIN|main|_|_
ARG|"()[]"|_|_
ARG|2|_|_
CALL|values|make|2
ARG|values|_|_
ARG|1|_|_
CALL|value|__index_get|2
UNIT|expected|_|_
CMP_EQ|equal|value|expected
JUMP_IF_FALSE|bad|equal|_
RET|42|_|_
LABEL|bad|_|_
RET|1|_|_
FUNC_END|main|_|_
IR
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/make-unit.ir" "$work/make-unit"
status=0; timeout 15 "$work/make-unit" || status=$?
test "$status" -eq 42
echo 'independent IR nonempty unit array defaults: PASS'

for spelling in '[]()' '[]unit' 'unit[]'; do
    sed "s/()\[\]/$spelling/" "$work/make-unit.ir" > "$work/alias-unit.ir"
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/alias-unit.ir" "$work/alias-unit"
    status=0; timeout 15 "$work/alias-unit" || status=$?
    test "$status" -eq 42
done
