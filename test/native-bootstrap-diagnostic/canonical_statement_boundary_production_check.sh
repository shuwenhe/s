#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-boundary.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:])
(work/'original.s').write_text((root/'test/selfhost/newline-negative-tail/main.s').read_text())
cases={
'ordinary': 'a := 43; x := a - 1; return x',
'unary': 'y := -1; return y + 43',
'operator_before_newline': 'a := 43; x := a -\n 1; return x',
'operator_after_newline': 'a := 43; x := a\n - 1; return x',
'parenthesized': 'a := 43; x := (a\n - 1); return x',
'negative_rhs': 'a := 41; return a - -1',
'if_binding': 'x := if input > 0 { 44 } else { 43 }\n - 1; return x',
'if_return': 'return if input > 0 { 44 } else { 43 }\n - 1',
'if_parenthesized': 'return (if input > 0 { 44 } else { 43 })\n - 1',
'comment_continuation': 'a := 43; x := a /* continued\n here */ -1; return x',
'legacy_case': 'return switch input { case 0: if input > 0 { return 1 }\n -1\n default: 1 } + 43',
}
for name,body in cases.items():
 (work/(name+'.s')).write_text('package main\nfunc main(int input) int { '+body+' }\n')
for name,separator in [('comment',' // separate\n'),('block_comment',' /* comment\n separate */ '),('crlf','\r\n'),('semicolon','; '),('blank','\n\n')]:
 (work/(name+'.s')).write_text('package main\nfunc fallback(int input) int { if input > 0 { return input }'+separator+'-1\n}\nfunc main(int input) int { return fallback(input) + 43 }\n')
PY
for name in original ordinary unary operator_before_newline operator_after_newline parenthesized negative_rhs if_binding if_return if_parenthesized comment_continuation legacy_case comment block_comment crlf semicolon blank; do
    "$compiler" --compile-unit "$work/$name.sasm" "$work/$name.s"
    "$compiler" --emit-bin "$work/$name.sasm" "$work/$name"
    sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/$name"
    for input in 0 1 7; do
        expected=42
        case "$name" in
            comment|block_comment|crlf|semicolon|blank) if [ "$input" -gt 0 ]; then expected=$((input + 43)); fi ;;
            if_binding|if_return|if_parenthesized) if [ "$input" -gt 0 ]; then expected=43; fi ;;
            legacy_case) if [ "$input" -gt 0 ]; then expected=44; fi ;;
        esac
        status=0; timeout 10 "$work/$name" "$input" || status=$?
        test "$status" -eq "$expected" || { echo "$name input=$input exit=$status expected=$expected" >&2; exit 1; }
    done
done
for body in 'return () - 1' 'return 1 - ()'; do
    printf 'package main\nfunc main() int { %s }\n' "$body" > "$work/invalid.s"
    printf keep > "$work/rejected.sasm"
    if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/error.log" 2>&1; then
        echo 'accepted unit/integer subtraction' >&2; exit 1
    fi
    rg -q 'e3018' "$work/error.log"
    test "$(cat "$work/rejected.sasm")" = keep
done
echo 'canonical native statement boundary: negative tails, unary/binary and multiline subtraction, expression-valued if, strict unit subtraction rejection: PASS'
