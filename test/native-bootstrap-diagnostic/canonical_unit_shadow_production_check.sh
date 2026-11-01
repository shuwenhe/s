#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-unit-shadow.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$work" <<'PY'
from pathlib import Path
import sys
w=Path(sys.argv[1]);cases={
'parameter': 'struct Event { string unit }\nfunc make(string unit) Event { Event { unit: unit } }\nfunc main() int { e := make("ok"); if e.unit == "ok" { return 42 }; return 1 }',
'local': 'func main() int { unit := 41; unit += 1; return unit }',
'boolean': 'func choose(bool unit) int { if unit { return 42 }; return 1 }\nfunc main() int { return choose(true) }',
'nested': 'func read(string unit) int { total := 0; if true { unit := 40; total = unit }; if unit == "ok" { return total + 2 }; return 1 }\nfunc main() int { return read("ok") }',
'literal': 'func empty(string unit) () { () }\nfunc main() int { empty("ok"); return 42 }',
'builtin': 'func empty() () { unit }\nfunc main() int { empty(); return 42 }',
'synthesized': 'func empty(string unit) () {}\nfunc main() int { empty("ok"); return 42 }',
}
for name,code in cases.items(): (w/(name+'.s')).write_text('package main\n'+code+'\n')
PY
for name in parameter local boolean nested literal builtin synthesized; do
 "$compiler" --compile-unit "$work/$name.sasm" "$work/$name.s"
 "$compiler" --emit-bin "$work/$name.sasm" "$work/$name"
 sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/$name"
 status=0; timeout 10 "$work/$name" || status=$?
 test "$status" -eq 42 || { echo "$name exit=$status expected=42" >&2; exit 1; }
done
printf keep > "$work/rejected.sasm"
for mode in argument return_type scalar; do
 case "$mode" in
  argument) code='func take(string value) int { return 42 }; func main() int { return take(()) }' ;;
  return_type) code='func wrong(string unit) () { unit }; func main() int { return 42 }' ;;
  scalar) code='func main() int { return () }' ;;
 esac
 printf 'package main\n%s\n' "$code" > "$work/invalid.s"
 if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/rejected.log" 2>&1; then echo 'accepted wrong unit type' >&2; exit 1; fi
 rg -q "e1002|e3004|e3008|return type:" "$work/rejected.log"
 test "$(cat "$work/rejected.sasm")" = keep
done
echo 'native unit binding precedence, nested scope, explicit/synthesized literals and strict rejection: PASS'
