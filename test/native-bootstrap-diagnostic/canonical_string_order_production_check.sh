#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-string-order.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$work" <<'PY'
from pathlib import Path
import sys
work = Path(sys.argv[1])
cases = {
    'digits': 'ch := "4"; if ch >= "0" && ch <= "9" { return 42 }; return 1',
    'operators': 'if "a" < "b" && "a" <= "a" && "b" > "a" && "b" >= "b" { return 42 }; return 1',
    'equal': 'if "same" < "same" || "same" > "same" { return 1 }; if "same" <= "same" && "same" >= "same" { return 42 }; return 2',
    'prefix': 'if "a" < "aa" && "aa" > "a" && "z" > "aa" { return 42 }; return 1',
    'empty': 'if "" < "a" && "a" > "" && "" <= "" && "" >= "" { return 42 }; return 1',
    'default': 'record := Empty {}; empty := record.text; if empty <= "" && empty >= "" && empty < "a" && "a" > empty { return 42 }; return 1',
    'unsigned': 'if "é" > "z" && "z" < "é" { return 42 }; return 1',
    'concatenated': 'prefix := "ab"; combined := prefix + "c"; if combined <= "abc" && combined >= "abc" && combined > prefix { return 42 }; return 1',
    'integers': 'if -2 < -1 && 0 <= 0 && 2 > 1 && 3 >= 3 { return 42 }; return 1',
}
for name, body in cases.items():
    (work / (name + '.s')).write_text('package main\nstruct Empty { string text }\nfunc main() int { ' + body + ' }\n')
PY
for name in digits operators equal prefix empty default unsigned concatenated integers; do
    "$compiler" --compile-unit "$work/$name.sasm" "$work/$name.s"
    "$compiler" --emit-bin "$work/$name.sasm" "$work/$name"
    sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/$name"
    status=0; timeout 10 "$work/$name" || status=$?
    test "$status" -eq 42 || { echo "$name exit=$status expected=42" >&2; exit 1; }
done
cat > "$work/dynamic.s" <<'S'
package main
func main(int input) int {
    left := "a"
    if input > 0 { left = left + "b" }
    if left < "ab" { return 40 }
    if left <= "ab" && left >= "ab" { return 42 }
    return 1
}
S
"$compiler" --compile-unit "$work/dynamic.sasm" "$work/dynamic.s"
"$compiler" --emit-bin "$work/dynamic.sasm" "$work/dynamic"
for pair in '0 40' '1 42' '7 42'; do
    read -r input expected <<< "$pair"
    status=0; timeout 10 "$work/dynamic" "$input" || status=$?
    test "$status" -eq "$expected"
done
for op in '<' '<=' '>' '>='; do
    for expression in "\"a\" $op 1" "1 $op \"a\"" "true $op false"; do
        printf 'package main\nfunc main() bool { return %s }\n' "$expression" > "$work/invalid.s"
        printf keep > "$work/rejected.sasm"
        if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/error.log" 2>&1; then
            echo "accepted invalid ordering: $expression" >&2; exit 1
        fi
        rg -q 'e3019' "$work/error.log"
        test "$(cat "$work/rejected.sasm")" = keep
    done
done
echo 'canonical native string ordering: operators, byte/length order, empty/default, dynamic values and strict rejection: PASS'
