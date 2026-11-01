#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-break.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$work" <<'PY'
from pathlib import Path
import sys
work = Path(sys.argv[1])
cases = {
    'while': 'i := 0; while i < 10 { i += 1; if i == 2 { break } }; return i + 40',
    'infinite': 'i := 0; for { i += 1; if i == 2 { break } }; return i + 40',
    'post': 'i := 0; for ; i < 10; i++ { if i == 2 { break } }; return i + 40',
    'unconditional': 'value := 1; while true { value = 42; break; value = 9 }; return value',
    'all': 'value := 0; for value < 10 { if value == 0 { value = 42; break } else { value = 7; break }; value = 9 }; return value',
    'nested': 'value := 0; for i := 0; i < 3; i++ { for { value += 2; break }; if i == 1 { break }; value += 1 }; return value + 37',
    'mixed': 'value := 0; for i := 0; i < 10; i++ { if i == 1 { continue }; if i == 4 { break }; value += i }; return value + 37',
    'switch': 'i := 0; for i < 10 { i += 1; switch i { 2: break, _: (), }; i += 1 }; return i + 32',
    'switch_break': 'i := 0; for { i += 1; switch i { 2: break, _: (), } }; return i + 40',
    'legacy': 'value := 0; for i := 0; i < 10; i++ { switch i { case 2: break; value += 100; default: value += 1 } }; return value + 40',
    'aggregate': 'values := [0]; saved := values; for i := 0; i < 10; i++ { values = append(values, i); if i == 2 { values[0] = 38; break } }; if saved[0] != 0 || len(saved) != 1 { return 1 }; return values[0] + len(values)',
    'shadow': 'value := 40; for i := 0; i < 10; i++ { value += 2; { value := 99; if value == 99 { break } } }; return value',
    'short': 'value := 0; while value < 10 && value >= 0 { value += 1; if value == 2 { break } }; return value + 40',
    'condition_effect': 'value := 0; while (if value < 10 { value += 1; true } else { false }) { if value == 2 { break } }; return value + 40',
    'return': 'value := 0; for value < 10 { if value == 0 { value = 2; break } else { return 1 } }; return value + 40',
    'parallel': 'first := 2; second := 4; for { temporary := first; first = second; second = temporary; break }; return first * 10 + second',
    'if_condition': 'value := 40; for { if { value += 2; break; true } { value = 9 }; value = 9 }; return value',
    'switch_subject': 'value := 40; for { switch { value += 2; break } { _: value = 9, }; value = 9 }; return value',
    'loop_condition': 'value := 40; for { while ({ value += 2; break; true }) { value = 1 }; value = 9 }; return value',
    'loop_init': 'value := 40; for { for ignored := { value += 2; break; 1 }; true; ignored++ { value = 1 }; value = 9 }; return value',
}
for name, body in cases.items():
    (work / (name + '.s')).write_text('package main\nfunc main() int { ' + body + ' }\n')
PY
for name in while infinite post unconditional all nested mixed switch switch_break legacy aggregate shadow short condition_effect return parallel if_condition switch_subject loop_condition loop_init; do
    "$compiler" --compile-unit "$work/$name.sasm" "$work/$name.s"
    "$compiler" --emit-bin "$work/$name.sasm" "$work/$name"
    sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/$name"
    status=0; timeout 10 "$work/$name" || status=$?
    test "$status" -eq 42 || { echo "$name exit=$status expected=42" >&2; exit 1; }
done
cat > "$work/dynamic.s" <<'S'
package main
func main(int input) int {
    value := 0
    for i := 0; i < input; i++ {
        if i == 2 && input < 5 { value += 20; break }
        if i == 5 { value += 100; break }
        value += 1
    }
    return value
}
S
"$compiler" --compile-unit "$work/dynamic.sasm" "$work/dynamic.s"
"$compiler" --emit-bin "$work/dynamic.sasm" "$work/dynamic"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/dynamic"
for pair in '-1 0' '0 0' '1 1' '2 2' '3 22' '5 5' '6 105' '10 105'; do
    read -r input expected <<< "$pair"
    status=0; timeout 10 "$work/dynamic" "$input" || status=$?
    test "$status" -eq "$expected" || { echo "dynamic input=$input exit=$status expected=$expected" >&2; exit 1; }
done
for body in 'break; return 42' 'if true { break }; return 42' 'switch 1 { _: break, }; return 42'; do
    printf 'package main\nfunc main() int { %s }\n' "$body" > "$work/invalid.s"
    printf keep > "$work/rejected.sasm"
    if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/rejected.log" 2>&1; then
        echo 'accepted break outside loop' >&2; exit 1
    fi
    rg -q 'e3071|break outside loop' "$work/rejected.log"
    test "$(cat "$work/rejected.sasm")" = keep
done
echo 'canonical native break: loop exits, post skipping, nested/switch control, phi values, snapshots and rejection: PASS'
