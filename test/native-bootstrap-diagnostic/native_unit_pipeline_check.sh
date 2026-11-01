#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-unit-pipeline.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "unit pipeline artifacts: $work" >&2; fi' EXIT
make -C "$root" compiler > "$work/build.log" 2>&1
compiler="$root/bin/s_compiler"
cat > "$work/program.s" <<'S'
package main
func pass(() first, int a, () third, int b, () fifth, int c, () seventh, int d) () {
    local := first
    local = third
    return seventh
}
func consume(() value) int { return 42 }
func empty() () {}
func no_result() {}
func main() int {
    () canonical = ()
    unit alias = canonical
    first := alias
    ignored := no_result()
    second := empty()
    third := pass(first, 1, second, 2, (), 3, (), 4)
    return consume(third)
}
S
"$compiler" --compile-unit "$work/program.sasm" "$work/program.s"
"$compiler" --emit-bin "$work/program.sasm" "$work/program"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/program"
status=0; timeout 15 "$work/program" || status=$?
test "$status" -eq 42
python3 - "$work" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);cases={
 'wrong_arg': 'func take(int value) int { return value }\nfunc main() int { return take(()) }',
 'wrong_unit_arg': 'func take(() value) int { return 42 }\nfunc main() int { return take(0) }',
 'wrong_return': 'func wrong() int { return () }\nfunc main() int { return wrong() }',
 'wrong_unit_return': 'func wrong() () { return 0 }\nfunc main() int { wrong(); return 42 }',
 'wrong_assignment': 'func main() int { value := (); value = 0; return 42 }',
 'arithmetic': 'func main() int { value := (); return value + 1 }',
 'arity': 'func take() int { return 42 }\nfunc main() int { return take(()) }',
 'missing': 'func main() int { value := ; return 42 }',
}
for name,body in cases.items(): (p/(name+'.s')).write_text('package main\n'+body+'\n')
PY
printf 'preserve artifact\n' > "$work/output"
cp "$work/output" "$work/saved"
for name in wrong_arg wrong_unit_arg wrong_return wrong_unit_return wrong_assignment arithmetic arity missing; do
    if "$compiler" --compile-unit "$work/output" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "S native pipeline accepted invalid unit use: $name" >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
done
echo 'S unit frontend -> typed MIR -> SSA -> amd64 ELF and ABI: PASS'
