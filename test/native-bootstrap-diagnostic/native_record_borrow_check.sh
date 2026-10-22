#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work="$root/.bootstrap/native-record-borrow"
mkdir -p "$work"
cat > "$work/value.s" <<'S'
package main
struct cell { int number }
func set(target* cell, int number) { target.number = number }
func main() int {
    value := cell { number: 1 }
    set(value, 42)
    return value.number
}
S
"$root/bin/s_seed" --compile-native-unit "$work/value.ir" "$work/value.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/value.ir" "$work/value"
status=0; "$work/value" || status=$?
test "$status" -eq 42
printf 'proven nonescaping record borrow mutation: PASS\n'
printf 'preserve output\n' > "$work/output"
cp "$work/output" "$work/saved"
cat > "$work/escape.s" <<'S'
package main
struct cell { int number }
func escape(target* cell) cell { return target }
func main() int { return 42 }
S
cat > "$work/alias.s" <<'S'
package main
struct cell { int number }
func two(first* cell, second* cell) { return }
func main() int { value := cell {}; two(value, value); return 42 }
S
cat > "$work/effects.s" <<'S'
package main
struct cell { int number }
func effect() int { return 42 }
func set(target* cell, int number) { target.number = number }
func main() int { value := cell {}; set(value, effect()); return 42 }
S
for name in escape alias effects; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "unsafe borrow accepted: $name" >&2; exit 1
    fi
    grep -q 'unproven' "$work/$name.log"
    cmp "$work/output" "$work/saved"
done
python3 - "$work" <<'PY'
import pathlib,sys
w=pathlib.Path(sys.argv[1]); original=(w/'value.ir').read_text()
(w/'escape.ir').write_text(original.replace('MOV|target.number|number|_', 'RET|target|_|_'))
(w/'erased.ir').write_text(original.replace('ARG|value|mutable_borrow|_', 'ARG|value|_|_'))
(w/'owner.ir').write_text(original.replace('record-field:main.cell|number|int', 'record-field:main.cell|number|int*'))
(w/'runtime-name.ir').write_text(original.replace(':set|', ':len|').replace('FUNC_BEGIN|set|', 'FUNC_BEGIN|len|').replace('FUNC_END|set|', 'FUNC_END|len|').replace('|set|2', '|len|2'))
(w/'numeric.ir').write_text(original.replace('MOV|t1|"t1"|_', 'MOV|t1|7|_'))
(w/'uninitialized.ir').write_text(original.replace('MOV|value|t1|_', 'JUMP|skip|_|_\nMOV|value|t1|_\nLABEL|skip|_|_'))
(w/'arity.ir').write_text(original.replace('ARG|value|mutable_borrow|_\nARG|42|_|_\nCALL|t2|set|2', 'CALL|t2|set|0'))
(w/'orphan.ir').write_text(original.replace('borrow-param:set|target|main.cell', 'borrow-param:missing|target|main.cell'))
PY
cat > "$work/forbidden-tool" <<'S'
#!/bin/sh
printf called >> "$S_TEST_TOOL_LOG"
exit 99
S
chmod +x "$work/forbidden-tool"
rm -f "$work/tools.log"
for name in runtime-name numeric uninitialized arity escape erased owner orphan; do
    if S_SOURCE_ROOT="$root" S_TEST_TOOL_LOG="$work/tools.log" \
        S_BOOTSTRAP_AS="$work/forbidden-tool" S_BOOTSTRAP_LD="$work/forbidden-tool" \
        "$root/bin/s_seed" --emit-standalone-amd64 "$work/$name.ir" "$work/output" > "$work/$name-ir.log" 2>&1; then
        echo "unsafe external borrow IR accepted: $name" >&2; exit 1
    fi
    grep -Eq 'unproven|unsupported_owner' "$work/$name-ir.log"
    test ! -e "$work/tools.log"
    cmp "$work/output" "$work/saved"
done
if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-hosted-program "$work/value.ir" "$work/output" > "$work/hosted.log" 2>&1; then
    echo 'hosted backend silently accepted native borrow IR' >&2; exit 1
fi
grep -q 'requires the standalone native backend' "$work/hosted.log"
cmp "$work/output" "$work/saved"
echo 'borrow escape/alias/effects and forged IR reject before output/tools: PASS'
# Exercise the real DFA module, including its unused pointer parameters.
# Minimal dependency types isolate this regression from other CFG algorithms.
cat > "$work/dfa-dependencies.s" <<'S'
package compile.internal.ir
struct ir_function { int marker }
struct control_flow_graph { int marker }
struct cfg_block { int marker }
func main() int {
    value := int_set {}
    int_set_add(value, 1)
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/dfa.ir" "$root/src/cmd/compile/internal/ir/dfa.s" "$work/dfa-dependencies.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/dfa.ir" "$work/dfa"
status=0; "$work/dfa" || status=$?
test "$status" -eq 42
echo 'real dfa.s source and standalone emission: PASS (isolated dependency types)'

cat > "$work/internal-owner.s" <<'S'
package compile.internal.ir
struct owner { int* pointer }
func main() int {
    if false { value := owner {}; return 1 }
    return 42
}
S
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/internal-owner.s" > "$work/internal-owner.log" 2>&1; then
    echo 'compiler package bypassed resource ownership checks' >&2; exit 1
fi
grep -q 'unsupported_owner' "$work/internal-owner.log"
cmp "$work/output" "$work/saved"
echo 'compiler package has no ownership exemption: PASS'
