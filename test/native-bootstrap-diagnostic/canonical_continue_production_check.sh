#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-continue.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$work" <<'PY'
from pathlib import Path
import sys
w=Path(sys.argv[1]); cases={
'while': 'i := 0; total := 0; while i < 6 { i += 1; if i % 2 == 1 { continue }; total += i }; return total + 30',
'condition': 'i := 0; total := 0; for i < 6 { i += 1; if i % 2 == 1 { continue }; total += i }; return total + 30',
'infinite': 'i := 0; for { i += 1; if i == 6 { return 42 }; continue }; return 1',
'post': 'total := 0; for i := 0; i < 6; i++ { if i < 3 { continue }; total += i }; return total + 30',
'nested': 'total := 0; for i := 0; i < 3; i++ { for j := 0; j < 4; j++ { if j == 1 { continue }; total += j }; if i == 1 { continue }; total += 1 }; return total + 25',
'legacy': 'total := 0; for i := 0; i < 3; i++ { switch i { case 0: continue; total += 100; default: total += i } }; return total + 39',
'switch': 'total := 0; for i := 0; i < 5; i++ { switch i { 1: continue, 3: continue, _: (), }; total += i }; return total + 36',
'all': 'total := 0; for i := 0; i < 6; i++ { total += 1; if i >= 0 { continue } else { continue }; total += 1000 }; return total + 36',
'aggregate': 'values := [0]; saved := values; for i := 0; i < 6; i++ { values = append(values, i); if i < 4 { continue }; values[0] += i }; if saved[0] != 0 || len(saved) != 1 { return 1 }; return values[0] + len(values) + 26',
}
for name,body in cases.items(): (w/(name+'.s')).write_text('package main\nfunc main() int { '+body+' }\n')
PY
for name in while condition infinite post nested switch legacy all aggregate; do
 "$compiler" --compile-unit "$work/$name.sasm" "$work/$name.s"
 "$compiler" --emit-bin "$work/$name.sasm" "$work/$name"
 sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/$name"
 status=0; timeout 10 "$work/$name" || status=$?
 test "$status" -eq 42 || { echo "$name exit=$status expected=42" >&2; exit 1; }
done
cat > "$work/dynamic.s" <<'S'
package main
func main(int input) int {
    total := 0
    for i := 0; i < input; i++ { if i % 2 == 0 { continue }; total += i }
    return total
}
S
"$compiler" --compile-unit "$work/dynamic.sasm" "$work/dynamic.s"
"$compiler" --emit-bin "$work/dynamic.sasm" "$work/dynamic"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/dynamic"
for pair in '0 0' '6 9' '10 25' '13 36'; do
 read -r input expected <<< "$pair"
 status=0; timeout 10 "$work/dynamic" "$input" || status=$?
 test "$status" -eq "$expected" || { echo "dynamic input=$input exit=$status expected=$expected" >&2; exit 1; }
done
printf keep > "$work/rejected.sasm"
for body in 'continue; return 42' 'if true { continue }; return 42' 'switch 1 { _: continue, }; return 42'; do
 printf 'package main\nfunc main() int { %s }\n' "$body" > "$work/invalid.s"
 if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/rejected.log" 2>&1; then echo 'accepted continue outside loop' >&2; exit 1; fi
 rg -q "e3070|continue outside loop" "$work/rejected.log"
 test "$(cat "$work/rejected.sasm")" = keep
done
echo 'canonical native continue: while, post, nested, switch, all-backedge, aggregate and rejection: PASS'
