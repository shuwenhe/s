#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-option-payload.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "option payload artifacts: $work" >&2; fi' EXIT
# Isolate the exact production helper for execution; the bootstrap still uses
# the complete source closure without filtering any declarations.
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]);work=Path(sys.argv[2]);source=(root/'src/cmd/compile/internal/ast/ast.s').read_text()
start=source.index('func dump_for_expr(');end=source.find('\nfunc ',start+1)
helper=source[start:end if end>=0 else len(source)]
fixture='''package compile.internal.ast
import "std.option"
import "std.prelude"
struct expr { int literal }
struct for_expr { string[] names; option[box[expr]] iterable }
func dump_expr(expr value) string { if value.literal == 42 { return "42" } return "bad" }
func join_with(string[] values, string separator) string {
    text := ""; i := 0
    for i < len(values) { if i > 0 { text = text + separator } text = text + values[i]; i = i + 1 }
    return text
}
func absent() option[box[expr]] { return option.none }
'''+helper+'''
func main() int {
    some := for_expr { names: ["item"], iterable: option.some(box(expr { literal: 42 })) }
    none := for_expr { names: string[](), iterable: absent() }
    if dump_for_expr(some) != "for item in 42 {...}" { return 1 }
    if dump_for_expr(none) != "for (...) {...}" { return 2 }
    return 42
}
'''
(work/'production.s').write_text(fixture)
PY
"$root/bin/s_seed" --compile-native-unit "$work/production.ir" "$root/src/prelude/prelude.s" "$root/src/option/option.s" "$work/production.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/production.ir" "$work/production"
status=0; timeout 15 "$work/production" || status=$?
test "$status" -eq 42
python3 - "$work" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);common='''package main
import "std.option"
import "std.prelude"
struct expr { int literal }
struct for_expr { option[box[expr]] iterable }
'''
cases={
 'direct':'func wrong(for_expr value) int { return value.iterable.value.value.literal }',
 'none_payload':'func wrong(option[box[expr]] input) int { switch input { option.some(payload): payload.value.literal, option.none: payload.value.literal } }',
 'escaped':'func wrong(option[box[expr]] input) int { switch input { option.some(payload): 1, option.none: 0 } return payload.value.literal }',
 'unknown_subject':'func wrong(any input) result[int,string] { switch input { option.some(payload): result.ok(payload.value.literal), option.none: result.err("none") } }',
}
for name,body in cases.items(): (p/(name+'.s')).write_text(common+body+'\nfunc main() int { return 42 }\n')
PY
printf 'preserve\n' > "$work/output"
cp "$work/output" "$work/saved"
for name in direct none_payload escaped unknown_subject; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/prelude/prelude.s" "$root/src/option/option.s" "$root/src/result/result.s" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "unproven option payload accepted: $name" >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
    if grep -q 'PARSE_FAIL' "$work/$name.log"; then cat "$work/$name.log" >&2; exit 1; fi
done
grep -q 'unresolved' "$work/unknown_subject.log"
grep -q 'enum payload access requires a variant pattern' "$work/direct.log"
echo 'production for-expression option some/none and payload scope rejection: PASS'
