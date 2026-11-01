#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
compiler=${1:-"$root/bin/s_modular"}
closure=${2:-"$root/.bootstrap/modular/canonical-closure.txt"}
report=${3:-"$root/.bootstrap/modular/canonical-resolution-closure-report.txt"}

if [ ! -x "$compiler" ]; then
    echo "canonical-resolution-closure-check: compiler is not executable: $compiler" >&2
    exit 2
fi
if [ ! -f "$closure" ]; then
    echo "canonical-resolution-closure-check: closure manifest not found: $closure" >&2
    exit 2
fi

mkdir -p "$(dirname -- "$report")"
tmp="${report}.tmp.$$"
failures="${report}.failures.$$"
help_out="${report}.help.$$"
tokens_out="${report}.tokens.$$"
ast_out="${report}.ast.$$"
resolve_out="${report}.resolve.$$"
trap 'rm -f "$tmp" "$failures" "$help_out" "$tokens_out" "$ast_out" "$resolve_out"' EXIT HUP INT TERM
: >"$failures"

closure_files=0
ast_ok=0
resolution_ok=0
declaration_ref_ok=0
unresolved_names=0
unresolved_imports=0
ambiguous_names=0
declaration_identity_errors=0
resolution_crashes=0
post_boundary_errors=0
pre_boundary_errors=0
first_failure=""
first_failure_stage=""
first_failure_class=""

resolve_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$root" "$1" ;;
    esac
}

first_location() {
    sed -n 's/.*:\([0-9][0-9]*\):\([0-9][0-9]*\):.*/line=\1 column=\2/p' "$1" | head -n 1
}

record_first_failure() {
    file=$1
    stage=$2
    class=$3
    if [ -z "$first_failure" ]; then
        first_failure=$file
        first_failure_stage=$stage
        first_failure_class=$class
    fi
}

has_resolution_stop_point() {
    status=0
    "$compiler" help >"$help_out" 2>&1 || status=$?
    if grep -Eq '(^|[[:space:]])resolve([[:space:]]|$)' "$help_out"; then
        return 0
    fi
    status=0
    "$compiler" --help >"$help_out" 2>&1 || status=$?
    grep -Eq '(^|[[:space:]])resolve([[:space:]]|$)' "$help_out"
}

classify_resolution_failure() {
    status=$1
    output=$2
    if [ "$status" -ge 128 ]; then
        printf '%s\n' "RESOLUTION_CRASH"
    elif grep -Eiq 'declaration[-_ ]?ref|declaration identity|identity.*error|missing.*identity' "$output"; then
        printf '%s\n' "DECLARATION_IDENTITY_ERROR"
    elif grep -Eiq 'ambiguous|e1003' "$output"; then
        printf '%s\n' "AMBIGUOUS_NAME"
    elif grep -Eiq 'unresolved import|unknown import|module not found|import.*not found|cannot resolve import' "$output"; then
        printf '%s\n' "UNRESOLVED_IMPORT"
    elif grep -Eiq 'unresolved name|undefined identifier|undefined function|assignment to undefined name|cannot borrow an undefined name|unknown method|e1001|e3010|e3002|e3054|e1006' "$output"; then
        printf '%s\n' "UNRESOLVED_NAME"
    elif grep -Eiq 'type|arity|overload|semantic|e[23][0-9][0-9][0-9]|e1002|e1005' "$output"; then
        printf '%s\n' "POST_BOUNDARY_ERROR"
    else
        printf '%s\n' "POST_BOUNDARY_ERROR"
    fi
}

if ! has_resolution_stop_point; then
    while IFS= read -r entry || [ -n "$entry" ]; do
        case "$entry" in
            ''|'#'*) continue ;;
        esac
        case "$entry" in
            *.s) closure_files=$((closure_files + 1)) ;;
            *) continue ;;
        esac
    done <"$closure"
    {
        echo "STAGE 5/6 - RESOLUTION / DECLARATIONREF CLOSURE"
        echo "Scope: Stage1 reachable canonical source closure"
        echo "Required path: AST -> Name / Import Resolution -> DeclarationRef -> STOP"
        echo "Type Checking success is NOT required."
        echo "CanonicalTypeRef success is NOT required."
        echo "Full Semantic success is NOT required."
        echo "Lowering/MIR/backend success is NOT required."
        echo "compiler=$compiler"
        echo "closure=$closure"
        echo "resolution-stop-point=NOT_FOUND"
        echo "closure-files=$closure_files"
        echo "ast-ok=NOT_RUN"
        echo "resolution-ok=NOT_OBSERVABLE"
        echo "declaration-ref-ok=NOT_OBSERVABLE"
        echo "unresolved-names=NOT_OBSERVABLE"
        echo "unresolved-imports=NOT_OBSERVABLE"
        echo "ambiguous-names=NOT_OBSERVABLE"
        echo "declaration-identity-errors=NOT_OBSERVABLE"
        echo "resolution-crashes=NOT_OBSERVABLE"
        echo "post-boundary-errors=NOT_OBSERVABLE"
        echo "first-failure=resolution-stop-point"
        echo "first-failure-stage=5"
        echo "first-failure-class=NOT_OBSERVABLE"
        echo "stage5-resolution=NOT_OBSERVABLE"
        echo "stage6-declaration-ref=NOT_OBSERVABLE"
        echo "result=FAIL"
    } >"$tmp"
    mv "$tmp" "$report"
    cat "$report"
    exit 1
fi

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

    tokens_status=0
    "$compiler" tokens "$file" >"$tokens_out" 2>&1 || tokens_status=$?
    if [ "$tokens_status" -ne 0 ]; then
        pre_boundary_errors=$((pre_boundary_errors + 1))
        record_first_failure "$entry" "pre" "TOKEN_FAILURE"
        {
            echo "failure:"
            echo "  file=$entry"
            echo "  stage=pre"
            echo "  class=TOKEN_FAILURE"
            echo "  status=$tokens_status"
        } >>"$failures"
        continue
    fi

    ast_status=0
    "$compiler" ast "$file" >"$ast_out" 2>&1 || ast_status=$?
    if [ "$ast_status" -ne 0 ]; then
        pre_boundary_errors=$((pre_boundary_errors + 1))
        record_first_failure "$entry" "pre" "AST_FAILURE"
        location=$(first_location "$ast_out" || true)
        {
            echo "failure:"
            echo "  file=$entry"
            echo "  stage=pre"
            echo "  class=AST_FAILURE"
            [ -n "$location" ] && echo "  $location"
            echo "  status=$ast_status"
        } >>"$failures"
        continue
    fi
    ast_ok=$((ast_ok + 1))

    resolve_status=0
    "$compiler" resolve "$file" >"$resolve_out" 2>&1 || resolve_status=$?
    if [ "$resolve_status" -eq 0 ]; then
        resolution_ok=$((resolution_ok + 1))
        declaration_ref_ok=$((declaration_ref_ok + 1))
        continue
    fi

    class=$(classify_resolution_failure "$resolve_status" "$resolve_out")
    case "$class" in
        UNRESOLVED_NAME)
            unresolved_names=$((unresolved_names + 1))
            failure_stage="5"
            record_first_failure "$entry" "5" "$class"
            ;;
        UNRESOLVED_IMPORT)
            unresolved_imports=$((unresolved_imports + 1))
            failure_stage="5"
            record_first_failure "$entry" "5" "$class"
            ;;
        AMBIGUOUS_NAME)
            ambiguous_names=$((ambiguous_names + 1))
            failure_stage="5"
            record_first_failure "$entry" "5" "$class"
            ;;
        DECLARATION_IDENTITY_ERROR)
            declaration_identity_errors=$((declaration_identity_errors + 1))
            failure_stage="6"
            record_first_failure "$entry" "6" "$class"
            ;;
        RESOLUTION_CRASH)
            resolution_crashes=$((resolution_crashes + 1))
            failure_stage="5"
            record_first_failure "$entry" "5" "$class"
            ;;
        *)
            post_boundary_errors=$((post_boundary_errors + 1))
            failure_stage="post"
            record_first_failure "$entry" "post" "$class"
            ;;
    esac
    location=$(first_location "$resolve_out" || true)
    {
        echo "failure:"
        echo "  file=$entry"
        echo "  stage=$failure_stage"
        echo "  class=$class"
        [ -n "$location" ] && echo "  $location"
        echo "  status=$resolve_status"
    } >>"$failures"
done <"$closure"

if [ "$closure_files" -gt 0 ] &&
   [ "$ast_ok" -eq "$closure_files" ] &&
   [ "$resolution_ok" -eq "$closure_files" ] &&
   [ "$unresolved_names" -eq 0 ] &&
   [ "$unresolved_imports" -eq 0 ] &&
   [ "$ambiguous_names" -eq 0 ] &&
   [ "$resolution_crashes" -eq 0 ]; then
    stage5="CLOSED"
else
    stage5="NOT_CLOSED"
fi

if [ "$closure_files" -gt 0 ] &&
   [ "$ast_ok" -eq "$closure_files" ] &&
   [ "$declaration_ref_ok" -eq "$closure_files" ] &&
   [ "$declaration_identity_errors" -eq 0 ]; then
    stage6="CLOSED"
else
    stage6="NOT_CLOSED"
fi

if [ -z "$first_failure" ]; then
    first_failure="NONE"
    first_failure_stage="NONE"
    first_failure_class="NONE"
fi

{
    echo "STAGE 5/6 - RESOLUTION / DECLARATIONREF CLOSURE"
    echo "Scope: Stage1 reachable canonical source closure"
    echo "Required path: AST -> Name / Import Resolution -> DeclarationRef -> STOP"
    echo "Type Checking success is NOT required."
    echo "CanonicalTypeRef success is NOT required."
    echo "Full Semantic success is NOT required."
    echo "Lowering/MIR/backend success is NOT required."
    echo "compiler=$compiler"
    echo "closure=$closure"
    echo "resolution-stop-point=FOUND"
    echo "closure-files=$closure_files"
    echo "ast-ok=$ast_ok"
    echo "resolution-ok=$resolution_ok"
    echo "declaration-ref-ok=$declaration_ref_ok"
    echo "unresolved-names=$unresolved_names"
    echo "unresolved-imports=$unresolved_imports"
    echo "ambiguous-names=$ambiguous_names"
    echo "declaration-identity-errors=$declaration_identity_errors"
    echo "resolution-crashes=$resolution_crashes"
    echo "post-boundary-errors=$post_boundary_errors"
    echo "pre-boundary-errors=$pre_boundary_errors"
    echo "first-failure=$first_failure"
    echo "first-failure-stage=$first_failure_stage"
    echo "first-failure-class=$first_failure_class"
    echo "stage5-resolution=$stage5"
    echo "stage6-declaration-ref=$stage6"
    if [ "$stage5" = "CLOSED" ] && [ "$stage6" = "CLOSED" ]; then
        echo "result=PASS"
    else
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
