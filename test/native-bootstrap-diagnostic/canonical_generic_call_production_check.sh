#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-generic-call.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT

# Dropping the checked call identity or inferred type arguments must prevent
# these programs from specializing and executing their actual function bodies.
python3 - "$work" <<'PY'
from pathlib import Path
import sys
work = Path(sys.argv[1])
cases = {
    'scalar': 'func identity[t](t value) t { value }\nfunc main(int input) int { identity(input) + 41 }',
    'instances': 'func identity[t](t value) t { value }\nfunc main(int input) int { identity(input) + len(identity("hi")) + 39 }',
    'nested': 'func identity[t](t value) t { value }\nfunc relay[u](u value) u { identity(value) }\nfunc main(int input) int { relay(input) + 41 }',
    'recursive': 'func repeat[t](int count, t value) t { if count <= 0 { return value }; return repeat(count - 1, value) }\nfunc main(int input) int { repeat(3, input) + 41 }',
    'typed': 'func select[t](bool first, t left, t right) t { if first { return left }; return right }\nfunc main(int input) int { select(true, input, 99) + 41 }',
    'qualified': 'func main(int input) int { helper.identity(input) + 41 }\npackage helper\nfunc identity[t](t value) t { value }',
}
for name, body in cases.items():
    (work / (name + '.s')).write_text('package main\n' + body + '\n')
PY
for name in scalar instances nested recursive typed qualified; do
    "$compiler" --compile-unit "$work/$name.sasm" "$work/$name.s"
    "$compiler" --emit-bin "$work/$name.sasm" "$work/$name"
    sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/$name"
    for pair in '0 41' '1 42' '7 48'; do
        read -r input expected <<< "$pair"
        status=0; timeout 10 "$work/$name" "$input" || status=$?
        test "$status" -eq "$expected" || { echo "$name input=$input exit=$status expected=$expected" >&2; exit 1; }
    done
done

for body in \
    'func same[t](t left, t right) t { left }; func main() int { same(1, true) }' \
    'func identity[t](t value) t { value }; func main() int { identity() }' \
    'func identity[t](t value) t { value }; func main() int { identity(true) }'; do
    printf 'package main\n%s\n' "$body" > "$work/invalid.s"
    printf keep > "$work/rejected.sasm"
    if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/rejected.log" 2>&1; then
        echo 'accepted invalid generic call' >&2
        exit 1
    fi
    rg -q 'canonical semantic:' "$work/rejected.log"
    test "$(cat "$work/rejected.sasm")" = keep
done
echo 'canonical native generic calls: inference, distinct instances, nested calls, recursion, qualified calls and rejection: PASS'
