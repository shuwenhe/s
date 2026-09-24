#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
compiler=${1:-"$root/bin/s_modular"}
closure=${2:-"$root/.bootstrap/modular/canonical-closure.txt"}
report=${3:-"$root/.bootstrap/modular/canonical-parser-closure-report.txt"}

if [ ! -x "$compiler" ]; then
    echo "canonical-parser-closure-check: compiler is not executable: $compiler" >&2
    exit 2
fi
if [ ! -f "$closure" ]; then
    echo "canonical-parser-closure-check: closure manifest not found: $closure" >&2
    exit 2
fi

mkdir -p "$(dirname -- "$report")"
tmp="${report}.tmp.$$"
failures="${report}.failures.$$"
lex_out="${report}.lex.$$"
ast_out="${report}.ast.$$"
trap 'rm -f "$tmp" "$failures" "$lex_out" "$ast_out"' EXIT HUP INT TERM
: >"$failures"

closure_files=0
lex_ok=0
parsed_ok=0
lex_errors=0
parse_errors=0
unsupported_syntax=0
source_defects=0
parser_crashes=0
regression_failures=0

resolve_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$root" "$1" ;;
    esac
}

first_location() {
    sed -n 's/.*:\([0-9][0-9]*\):\([0-9][0-9]*\):.*/line=\1 column=\2/p' "$1" | head -n 1
}

classify_ast_failure() {
    status=$1
    output=$2
    if [ "$status" -ge 128 ]; then
        printf '%s\n' "PARSER_CRASH"
    elif grep -Eiq 'unsupported|not supported|NYI|unimplemented' "$output"; then
        printf '%s\n' "UNSUPPORTED_SYNTAX"
    elif grep -Eiq "expected ['\")]|unexpected end|unterminated|missing ['\")]|source defect" "$output"; then
        printf '%s\n' "SOURCE_DEFECT"
    elif grep -Eiq 'parse|parser|syntax|expected|unexpected' "$output"; then
        printf '%s\n' "PARSE_ERROR"
    else
        printf '%s\n' "REGRESSION_FAILURE"
    fi
}

while IFS= read -r entry || [ -n "$entry" ]; do
    case "$entry" in
        ''|'#'*) continue ;;
    esac
    case "$entry" in
        *.s) ;;
        *) continue ;;
    esac

    file=$(resolve_path "$entry")
    closure_files=$((closure_files + 1))

    lex_status=0
    "$compiler" tokens "$file" >"$lex_out" 2>&1 || lex_status=$?
    if [ "$lex_status" -ne 0 ]; then
        lex_errors=$((lex_errors + 1))
        location=$(first_location "$lex_out" || true)
        {
            echo "failure:"
            echo "  file=$entry"
            echo "  class=LEX_ERROR"
            [ -n "$location" ] && echo "  $location"
            echo "  status=$lex_status"
        } >>"$failures"
        continue
    fi
    lex_ok=$((lex_ok + 1))

    ast_status=0
    "$compiler" ast "$file" >"$ast_out" 2>&1 || ast_status=$?
    if [ "$ast_status" -eq 0 ]; then
        parsed_ok=$((parsed_ok + 1))
        continue
    fi

    class=$(classify_ast_failure "$ast_status" "$ast_out")
    case "$class" in
        PARSE_ERROR) parse_errors=$((parse_errors + 1)) ;;
        UNSUPPORTED_SYNTAX) unsupported_syntax=$((unsupported_syntax + 1)) ;;
        SOURCE_DEFECT) source_defects=$((source_defects + 1)) ;;
        PARSER_CRASH) parser_crashes=$((parser_crashes + 1)) ;;
        *) regression_failures=$((regression_failures + 1)) ;;
    esac
    location=$(first_location "$ast_out" || true)
    {
        echo "failure:"
        echo "  file=$entry"
        echo "  class=$class"
        [ -n "$location" ] && echo "  $location"
        echo "  status=$ast_status"
    } >>"$failures"
done <"$closure"

{
    echo "STAGE 3 - PARSER CLOSURE"
    echo "Scope: Stage1 reachable canonical source closure"
    echo "Required path: Source -> Lexer -> Tokens -> Parser -> AST"
    echo "Semantic success is NOT required."
    echo "Lowering success is NOT required."
    echo "MIR success is NOT required."
    echo "Codegen success is NOT required."
    echo "compiler=$compiler"
    echo "closure=$closure"
    echo "closure-files=$closure_files"
    echo "lex-ok=$lex_ok"
    echo "parsed-ok=$parsed_ok"
    echo "ast-ok=$parsed_ok"
    echo "lex-errors=$lex_errors"
    echo "parse-errors=$parse_errors"
    echo "unsupported-syntax=$unsupported_syntax"
    echo "source-defects=$source_defects"
    echo "parser-crashes=$parser_crashes"
    echo "regression-failures=$regression_failures"
    if [ "$closure_files" -gt 0 ] &&
       [ "$lex_ok" -eq "$closure_files" ] &&
       [ "$parsed_ok" -eq "$closure_files" ] &&
       [ "$lex_errors" -eq 0 ] &&
       [ "$parse_errors" -eq 0 ] &&
       [ "$unsupported_syntax" -eq 0 ] &&
       [ "$source_defects" -eq 0 ] &&
       [ "$parser_crashes" -eq 0 ] &&
       [ "$regression_failures" -eq 0 ]; then
        echo "stage3-parser=CLOSED/FROZEN"
        echo "result=PASS"
    else
        echo "stage3-parser=CURRENT/NOT_CLOSED"
        echo "result=FAIL"
    fi
    cat "$failures"
} >"$tmp"

mv "$tmp" "$report"
cat "$report"

if grep -qx 'result=PASS' "$report"; then
    exit 0
fi
exit 1
