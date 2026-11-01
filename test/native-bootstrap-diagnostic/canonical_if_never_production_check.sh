#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-if-never.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root, work = map(Path, sys.argv[1:])
(work/'original.s').write_text((root/'test/selfhost/if-never-merge/main.s').read_text())
cases = {
    'break_then': 'i := 0; for i < 10 { if i == 2 { break } else { i += 1 } }; return i + 40',
    'break_else': 'i := 0; for i < 10 { if i != 2 { i += 1 } else { break } }; return i + 40',
    'continue_then': 'i := 0; total := 0; for i < 4 { i += 1; if i < 3 { continue } else { total += i } }; return total + 35',
    'continue_else': 'i := 0; total := 0; for i < 4 { i += 1; if i >= 3 { total += i } else { continue } }; return total + 35',
    'return_then': 'if input == 0 { return 42 } else { () }; return 43',
    'return_else': 'if input == 0 { () } else { return 43 }; return 42',
    'value_then': 'value := if input == 0 { 42 } else { return 43 }; return value',
    'value_else': 'value := if input == 0 { return 42 } else { 43 }; return value',
    'both': 'if input == 0 { return 42 } else { return 43 }',
    'nested': 'value := if input == 0 { if input < 0 { return 1 } else { 42 } } else { return 43 }; return value',
    'string': 'value := if input == 0 { "answer" } else { return 43 }; if value == "answer" { return 42 }; return 1',
    'record': 'value := if input == 0 { return 42 } else { Record { value: 43 } }; return value.value',
    'bool': 'value := if input == 0 { true } else { return 43 }; if value { return 42 }; return 1',
    'bindings': 'value := 0; if input == 0 { value = 42 } else { return 43 }; return value',
}
for name, body in cases.items():
    (work/(name+'.s')).write_text('package main\nstruct Record { int value }\nfunc main(int input) int { '+body+' }\n')
PY
for name in original break_then break_else continue_then continue_else return_then return_else value_then value_else both nested string record bool bindings; do
    "$compiler" --compile-unit "$work/$name.sasm" "$work/$name.s"
    "$compiler" --emit-bin "$work/$name.sasm" "$work/$name"
    sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/$name"
    for input in 0 1; do
        expected=42
        case "$name" in original|break_then|break_else|continue_then|continue_else) ;; *) expected=$((42 + input));; esac
        status=0; timeout 10 "$work/$name" "$input" || status=$?
        test "$status" -eq "$expected" || { echo "$name input=$input exit=$status expected=$expected" >&2; exit 1; }
    done
done
for body in \
    'return switch input { 0: 42, _: panic("expected panic"), }' \
    'return switch input { 0: panic("expected panic"), _: 42, }' \
    'value := if input == 0 { 42 } else { panic("expected panic") }; return value'; do
    printf 'package main\nfunc main(int input) int { %s }\n' "$body" > "$work/panic.s"
    "$compiler" --compile-unit "$work/panic.sasm" "$work/panic.s"
    "$compiler" --emit-bin "$work/panic.sasm" "$work/panic"
    sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/panic"
    for input in 0 1; do
        expected=42
        case "$body" in *'0: panic'*) test "$input" -ne 0 || expected=101 ;; *) test "$input" -eq 0 || expected=101 ;; esac
        status=0; timeout 10 "$work/panic" "$input" > "$work/panic.out" 2>&1 || status=$?
        test "$status" -eq "$expected" || { echo "panic branch input=$input exit=$status expected=$expected" >&2; exit 1; }
        if test "$expected" -eq 101; then rg -q 'expected panic' "$work/panic.out"; fi
    done
done
for body in \
    'value := if input == 0 { 42 } else { true }; return 42' \
    'value := if input == 0 { true } else { 42 }; return 42' \
    'value := if input == 0 { () } else { 42 }; return 42'; do
    printf 'package main\nfunc main(int input) int { %s }\n' "$body" > "$work/invalid.s"
    printf keep > "$work/rejected.sasm"
    if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/error.log" 2>&1; then
        echo "accepted incompatible surviving branches: $body" >&2; exit 1
    fi
    rg -q 'e3015' "$work/error.log"
    test "$(cat "$work/rejected.sasm")" = keep
done
for body in \
    'if input == 0 { return true } else { () }; return 42' \
    'if input == 0 { () } else { return missing }; return 42' \
    'value := if input == 0 { return 42 } else { true }; return value' \
    'if 1 { return 42 } else { () }; return 43' \
    'if input == 0 { break } else { () }; return 42' \
    'if input == 0 { () } else { continue }; return 42'; do
    printf 'package main\nfunc main(int input) int { %s }\n' "$body" > "$work/invalid.s"
    printf keep > "$work/rejected.sasm"
    if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/error.log" 2>&1; then
        echo "accepted invalid terminating branch or result: $body" >&2; exit 1
    fi
    test "$(cat "$work/rejected.sasm")" = keep
done
echo 'canonical native if/never: break/continue/return, surviving values, both terminated, strict branch/result rejection: PASS'
