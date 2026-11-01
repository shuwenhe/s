#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-syntax-lexer.XXXXXX)
trap 'rm -rf "$work"' EXIT
lexer="$root/src/cmd/compile/internal/parser/syntax/lexer.s"
cat > "$work/decoy.s" <<'S'
package other
struct token { string value }
S
cat > "$work/main.s" <<'S'
package compile.internal.parser.syntax
func check(token[] tokens) int {
    if len(tokens) != 7 { return 1 }
    if tokens[0].kind != 5 || tokens[0].value != "func" || tokens[0].col != 11 { return 2 }
    if tokens[1].kind != 1 || tokens[1].value != "answer" || tokens[1].col != 16 { return 3 }
    if tokens[2].kind != 73 || tokens[2].col != 23 { return 4 }
    if tokens[3].kind != 2 || tokens[3].value != "42" || tokens[3].col != 26 { return 5 }
    if tokens[4].kind != 86 || tokens[4].line != 1 || tokens[4].col != 28 { return 6 }
    if tokens[5].kind != 3 || tokens[5].value != "ok" || tokens[5].line != 2 || tokens[5].col != 1 { return 7 }
    if tokens[6].kind != 0 || tokens[6].line != 2 || tokens[6].col != 5 { return 8 }
    return 42
}
func snapshot(token[] tokens) int {
    if tokens[0].value != "func" { return 1 }
    return 0
}
func main() int {
    source := "/* skip */" + "func answer := 42\n\"ok\""
    lex := lexer_new(source)
    lexer_tokenize(lex)
    tokens := lexer_get_tokens(lex)
    result := check(tokens)
    first := tokens[0]
    first.value = "changed"
    tokens[0] = first
    again := lexer_get_tokens(lex)
    return result + snapshot(again)
}
S
"$root/bin/s_seed" --compile-native-unit "$work/lexer.ir" "$lexer" "$work/decoy.s" "$work/main.s"
grep -Eq '^ARRAY_NEW\|[^|]+\|compile.internal.parser.syntax.token\[\]\|0$' "$work/lexer.ir"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/lexer.ir" "$work/lexer"
status=0; timeout 20 "$work/lexer" || status=$?
test "$status" -eq 42
cat > "$work/wrapper.s" <<'S'
package compile.internal.parser.syntax
func run(string source) int {
    lex := lexer_new(source)
    lexer_tokenize(lex)
    return 42
}
func relay(string source) int { return run(source) }
func main() int { return relay("func x") }
S
"$root/bin/s_seed" --compile-native-unit "$work/wrapper.ir" "$lexer" "$work/decoy.s" "$work/wrapper.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/wrapper.ir" "$work/wrapper"
status=0; timeout 20 "$work/wrapper" || status=$?
test "$status" -eq 42
python3 - "$work" <<'PY'
from pathlib import Path
import sys,json
p=Path(sys.argv[1])
# Exceed the old 1024-token allocation while keeping each source literal below
# the native IR operand limit; the lexer reads the resulting rope string.
text='x '*1030
chunks=[text[i:i+400] for i in range(0,len(text),400)]
source=' + '.join(json.dumps(x) for x in chunks)
(p/'stress.s').write_text('''package compile.internal.parser.syntax
func validate(token[] tokens) int {
    if len(tokens) != 1031 { return 1 }
    if tokens[1029].kind != 1 || tokens[1029].value != "x" || tokens[1029].col != 2059 { return 2 }
    if tokens[1030].kind != 0 || tokens[1030].col != 2061 { return 3 }
    return 42
}
func main() int {
    source := '''+source+'''
    lex := lexer_new(source)
    lexer_tokenize(lex)
    tokens := lexer_get_tokens(lex)
    return validate(tokens)
}
''')
# A declared record result is not ownership proof. Its body and actual call
# argument types must pass the independent native IR validator as well.
text=(p/'lexer.ir').read_text(); lines=text.splitlines()
start=lines.index('FUNC_BEGIN|lexer_new|_|_'); end=lines.index('FUNC_END|lexer_new|_|_')
wrong=list(lines)
for i in range(start,end):
 if lines[i].startswith('MOV|') and '.source|source|' in lines[i]:
  wrong[i]=lines[i].replace('|source|','|42|'); break
else: raise AssertionError('missing record source initialization')
(p/'wrong-field.ir').write_text('\n'.join(wrong)+'\n')
for i,line in enumerate(lines):
 if line.startswith('CALL|') and '|lexer_new|1' in line:
  assert lines[i-1].startswith('ARG|source|')
  lines[i-1]=lines[i-1].replace('ARG|source|','ARG|42|'); break
else: raise AssertionError('missing constructor call')
(p/'wrong-argument.ir').write_text('\n'.join(lines)+'\n')
text=(p/'wrapper.ir').read_text()
assert 'ARG|"func x"|_|_' in text
wrong=text.replace('ARG|"func x"|_|_','ARG|42|_|_')
(p/'wrong-caller.ir').write_text(wrong)
# Match the emitter's qualified-call fallback, without losing the proof at
# an alias spelling of the same actual function.
(p/'wrong-qualified-caller.ir').write_text(wrong.replace('|relay|1','|package.relay|1'))
entry=text.replace('FUNC_BEGIN|main|_|_', 'FUNC_BEGIN|main|_|_\nPARAM|source|_|_')
(p/'entry-parameter.ir').write_text(entry)
PY
"$root/bin/s_seed" --compile-native-unit "$work/stress.ir" "$lexer" "$work/decoy.s" "$work/stress.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/stress.ir" "$work/stress"
status=0; timeout 30 "$work/stress" || status=$?
test "$status" -eq 42
printf 'preserve output\n' > "$work/output"
cp "$work/output" "$work/saved"
cat > "$work/forbidden" <<'SH'
#!/bin/sh
printf called >> "$S_TEST_TOOL_LOG"
exit 99
SH
chmod +x "$work/forbidden"
for name in wrong-field wrong-argument wrong-caller wrong-qualified-caller entry-parameter; do
    if S_SOURCE_ROOT="$root" S_TEST_TOOL_LOG="$work/tools.log" S_BOOTSTRAP_AS="$work/forbidden" S_BOOTSTRAP_LD="$work/forbidden" \
        "$root/bin/s_seed" --emit-standalone-amd64 "$work/$name.ir" "$work/output" > "$work/$name.log" 2>&1; then
        echo "unproved constructor result accepted: $name" >&2; exit 1
    fi
    grep -Eq 'unproven|unsupported_owner' "$work/$name.log"
    cmp "$work/output" "$work/saved"
done
test ! -e "$work/tools.log"
echo 'real syntax lexer values, rope input, token snapshots, >1024 tokens and constructor provenance: PASS'
