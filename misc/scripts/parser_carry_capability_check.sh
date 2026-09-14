#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
compiler=${1:?usage: parser_carry_capability_check.sh COMPILER CLOSURE REPORT}
closure=${2:?missing closure}
report=${3:?missing report}
test -x "$compiler"
test -s "$closure"
mkdir -p "$(dirname "$report")"
work=$(mktemp -d "$(dirname "$report")/parser-carry.XXXXXX")
# Keep probe inputs and outputs for review, including unexpected build failures.
tmp=$work/report.txt
printf '%s\n' 'Phase 2.1c Parser Carry Capability Audit' \
    "compiler=$compiler" "evidence-directory=$work" \
    'scope=capability-audit-only' > "$tmp"
failed=0
for expected in 17 29; do
    input=$root/src/cmd/compile/internal/tests/fixtures/parser_carry_return${expected}.s
    build_status=0
    "$compiler" build "$input" -o "$work/return$expected" \
        > "$work/build$expected.log" 2>&1 || build_status=$?
    actual=NOT_RUN
    if [ "$build_status" -eq 0 ] && [ -x "$work/return$expected" ]; then
        actual=0
        "$work/return$expected" > "$work/run$expected.log" 2>&1 || actual=$?
    fi
    printf 'probe-return%s=expected:%s actual:%s build-status:%s\n' \
        "$expected" "$expected" "$actual" "$build_status" >> "$tmp"
    if [ "$actual" != "$expected" ]; then failed=1; fi
done
for source in src/cmd/compile/internal/syntax/syntax.s src/s/parser.s \
    src/s/lexer.s src/s/tokens.s src/s/ast.s; do
    if [ ! -f "$root/$source" ]; then
        state=SOURCE_MISSING
    elif grep -qxF "$source" "$closure"; then
        state=IN_CLOSURE
    else
        state=MISSING_FROM_CLOSURE
    fi
    printf 'parser-dependency=%s status=%s\n' "$source" "$state" >> "$tmp"
done
if rg -n 'func[[:space:]]+parse_s_tokens[[:space:]]*\(' "$root/src" \
    --glob '*.s' > "$work/parse-s-tokens-definitions.txt"; then
    printf '%s\n' 'parse-s-tokens-binding=CANDIDATE_DEFINITION_REQUIRES_REVIEW' >> "$tmp"
else
    status=$?
    [ "$status" -eq 1 ] || exit "$status"
    printf '%s\n' 'parse-s-tokens-binding=NO_EXPLICIT_S_DEFINITION_FOUND' >> "$tmp"
fi
if [ "$failed" -eq 1 ]; then
    printf '%s\n' 'parser-carry-status=BLOCKED' \
        'first-blocking-capability=source-dependent-function-body-execution' \
        'missing-capability-1=integer-return-semantics-not-preserved-by-stage1-build' \
        'next-cut=general-S-function-body-translation-and-integer-return-ABI' >> "$tmp"
else
    printf '%s\n' 'parser-carry-status=NOT_YET_PROVEN' \
        'integer-return-probe=PASS' \
        'first-blocking-capability=REQUIRES_FURTHER_AUDIT' >> "$tmp"
fi
printf '%s\n' 'remaining-capabilities=see-doc/parser-carry-capability.md' \
    's-parser-execution=NOT_PROVEN' \
    'production-parser-authority=BLOCKED' \
    'audit-exit-zero-means=report-produced-not-authority-proven' >> "$tmp"
cp "$tmp" "$report"
cat "$report"
