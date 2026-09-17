#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
entry_rel="src/cmd/compile/modular_build_main.s"
entry="$root/$entry_rel"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
historical_root="${P02_HISTORICAL_ROOT:-"$root/.bootstrap/selfhost/stage1"}"
report="${P02_EXECUTOR_COMPATIBILITY_REPORT:-"$root/.bootstrap/modular/p0.2-executor-compatibility-audit.txt"}"

tmp="${TMPDIR:-/tmp}/s-p0.2-executor.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$(dirname "$report")"

count_pattern() {
    local pattern="$1"
    local total=0
    local count
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        [ -f "$root/$rel" ] || continue
        count=$(rg -o -e "$pattern" "$root/$rel" 2>/dev/null | wc -l | tr -d ' ')
        total=$((total + count))
    done <"$closure"
    echo "$total"
}

files_with_pattern() {
    local pattern="$1"
    local total=0
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        [ -f "$root/$rel" ] || continue
        if rg -q -e "$pattern" "$root/$rel" 2>/dev/null; then
            total=$((total + 1))
        fi
    done <"$closure"
    echo "$total"
}

bool_file() {
    [ -f "$1" ] && echo YES || echo NO
}

bool_exec() {
    [ -x "$1" ] && echo YES || echo NO
}

closure_count=0
canonical_snapshot=NOT_FOUND
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if [ "$closure_count" -gt 0 ] && grep -qx "$entry_rel" "$closure"; then
        canonical_snapshot=FOUND
    fi
fi

result_method_calls=$(count_pattern '\.(is_err|is_ok|unwrap|unwrap_err)\(')
option_method_calls=$(count_pattern '\.(is_some|is_none|unwrap)\(')
qualified_import_uses=$(count_pattern '^[[:space:]]*"[^"]+\.[^"]+"|[[:alpha:]_][[:alnum:]_]*(\.[[:alpha:]_][[:alnum:]_]*){2,}')
tuple_return_sites=$(count_pattern '\)[[:space:]]*\([^)]*,[^)]*\)')

switch_sites=$(count_pattern '(^|[[:space:]])switch[[:space:]]')
reassignment_sites=$(count_pattern '(^|[[:space:]])[A-Za-z_][A-Za-z0-9_\\.\\[\\]]*[[:space:]]=')
for_sites=$(count_pattern '(^|[[:space:]])for[[:space:]]')
while_sites=$(count_pattern '(^|[[:space:]])while[[:space:]]')
struct_literal_sites=$(count_pattern '[A-Za-z_][A-Za-z0-9_\\.]*[[:space:]]*\{')

generic_sites=$(count_pattern '[A-Za-z_][A-Za-z0-9_]*\[[A-Za-z_][A-Za-z0-9_., ]*\]')
method_decl_sites=$(count_pattern '^func[[:space:]]*\(')
trait_sites=$(count_pattern '(^|[[:space:]])trait[[:space:]]')
enum_payload_sites=$(count_pattern 'enum[[:space:]]|::[A-Za-z_][A-Za-z0-9_]*\(')
ownership_sites=$(count_pattern 'borrow|move|drop|ownership|nll|loan')

std_env_sites=$(count_pattern 'std\.env|std\.process|std\.fs|std\.io')
vector_append_sites=$(count_pattern 'append\(|\.push\(')
result_type_sites=$(count_pattern 'result\.|src/cmd/compile/internal/syntax|src/result/result\.s')

representation_files=$(files_with_pattern '\.(is_err|is_ok|unwrap|unwrap_err)\(|option\[')
syntax_files=$(files_with_pattern '(^|[[:space:]])switch[[:space:]]|(^|[[:space:]])for[[:space:]]|(^|[[:space:]])while[[:space:]]|(^|[[:space:]])[A-Za-z_][A-Za-z0-9_\\.\\[\\]]*[[:space:]]=')
semantic_files=$(files_with_pattern 'trait[[:space:]]|func[[:space:]]*\(|\[[A-Za-z_][A-Za-z0-9_., ]*\]|ownership|borrow|move|drop|monomorph')
runtime_abi_files=$(files_with_pattern 'std\.env|std\.process|std\.fs|std\.io|append\(|\.push\(|result\.')

historical_exists=$(bool_file "$historical_root")
historical_executable=$(bool_exec "$historical_root")
historical_file=UNKNOWN
if [ "$historical_exists" = YES ]; then
    historical_file=$(file "$historical_root" 2>/dev/null || echo UNKNOWN)
fi

probe_exit=NOT_RUN
first_error=NONE
first_error_category=NOT_RUN
if [ "$historical_executable" = YES ] && [ -f "$entry" ]; then
    set +e
    "$historical_root" "$entry" "$tmp/current-canonical.ir" >"$tmp/stdout" 2>"$tmp/stderr"
    status=$?
    set -e
    probe_exit=$status
    if [ "$status" -eq 0 ]; then
        first_error=NONE
        first_error_category=NONE
    else
        first_error=$(sed -n '1p' "$tmp/stderr" "$tmp/stdout" 2>/dev/null | head -n 1)
        [ -n "$first_error" ] || first_error=UNKNOWN
        case "$first_error" in
            *"has no method 'is_err'"*|*"has no method 'unwrap'"*|*"has no method 'unwrap_err'"*|*"type '("*"has no method"*)
                first_error_category=REPRESENTATION_COMPATIBILITY
                ;;
            *"expected expression"*|*"expected"*|*"parse"*|*"PARSE_FAIL"*)
                first_error_category=SYNTAX_COMPATIBILITY
                ;;
            *"unknown symbol"*|*"unknown function"*|*"method"*|*"generic"*|*"semantic"*)
                first_error_category=SEMANTIC_COMPATIBILITY
                ;;
            *"runtime"*|*"ABI"*|*"link"*|*"undefined"*)
                first_error_category=ABI_RUNTIME_COMPATIBILITY
                ;;
            *)
                first_error_category=UNKNOWN_COMPATIBILITY
                ;;
        esac
    fi
fi

required_deltas=$((representation_files + syntax_files + semantic_files + runtime_abi_files))

requires_current_generic_system=UNKNOWN
requires_current_ownership_semantics=UNKNOWN
requires_current_method_resolution=UNKNOWN
requires_duplicate_semantic_authority=UNKNOWN
bounded_compatibility_layer=UNKNOWN
historical_root_verdict=REJECT_UNPROVEN_COMPATIBILITY_FRONTIER

if [ "$generic_sites" -gt 0 ]; then
    requires_current_generic_system=LIKELY
fi
if [ "$ownership_sites" -gt 0 ]; then
    requires_current_ownership_semantics=LIKELY
fi
if [ "$method_decl_sites" -gt 0 ] || [ "$result_method_calls" -gt 0 ]; then
    requires_current_method_resolution=LIKELY
fi

if [ "$first_error_category" = REPRESENTATION_COMPATIBILITY ] && \
   [ "$semantic_files" -le 3 ] && \
   [ "$requires_current_generic_system" != LIKELY ] && \
   [ "$requires_current_ownership_semantics" != LIKELY ]; then
    bounded_compatibility_layer=POSSIBLE
    requires_duplicate_semantic_authority=NO
    historical_root_verdict=PROBE_DEEPER_WITH_MECHANICAL_TRANSFORM
elif [ "$semantic_files" -gt 3 ] || \
     [ "$requires_current_generic_system" = LIKELY ] || \
     [ "$requires_current_ownership_semantics" = LIKELY ] || \
     [ "$requires_current_method_resolution" = LIKELY ]; then
    bounded_compatibility_layer=NO
    requires_duplicate_semantic_authority=LIKELY
    historical_root_verdict=REJECT_AS_PRIMARY_EXECUTOR_UNLESS_TRANSFORM_PROVES_MECHANICAL
fi

gate=RED
if [ "$historical_root_verdict" = PROBE_DEEPER_WITH_MECHANICAL_TRANSFORM ]; then
    gate=YELLOW
fi

{
    echo "P0.2 HISTORICAL_ROOT_CURRENT_CANONICAL_COMPATIBILITY_AUDIT"
    echo "P0_2_EXECUTOR_COMPATIBILITY=$gate"
    echo
    echo "canonical-snapshot=$canonical_snapshot"
    echo "canonical-snapshot-path=$closure"
    echo "canonical-snapshot-count=$closure_count"
    echo
    echo "historical-root:"
    echo "  path=$historical_root"
    echo "  exists=$historical_exists"
    echo "  executable=$historical_executable"
    echo "  file=$historical_file"
    echo
    echo "current-entry-probe:"
    echo "  command=<historical-root> $entry_rel <tmp-ir>"
    echo "  exit=$probe_exit"
    echo "  first-error=$first_error"
    echo "  first-error-category=$first_error_category"
    echo
    echo "compatibility-frontier-counts:"
    echo "  required-compatibility-deltas=$required_deltas"
    echo "  representation-files=$representation_files"
    echo "  representation-result-method-calls=$result_method_calls"
    echo "  representation-option-method-calls=$option_method_calls"
    echo "  representation-tuple-return-sites=$tuple_return_sites"
    echo "  syntax-files=$syntax_files"
    echo "  syntax-switch-sites=$switch_sites"
    echo "  syntax-reassignment-sites=$reassignment_sites"
    echo "  syntax-for-sites=$for_sites"
    echo "  syntax-while-sites=$while_sites"
    echo "  syntax-struct-literal-sites=$struct_literal_sites"
    echo "  semantic-files=$semantic_files"
    echo "  semantic-generic-sites=$generic_sites"
    echo "  semantic-method-decl-sites=$method_decl_sites"
    echo "  semantic-trait-sites=$trait_sites"
    echo "  semantic-enum-payload-sites=$enum_payload_sites"
    echo "  semantic-ownership-sites=$ownership_sites"
    echo "  runtime-abi-files=$runtime_abi_files"
    echo "  runtime-std-env-process-fs-io-sites=$std_env_sites"
    echo "  runtime-vector-append-sites=$vector_append_sites"
    echo "  runtime-result-type-sites=$result_type_sites"
    echo "  qualified-import-uses=$qualified_import_uses"
    echo
    echo "authority-risk:"
    echo "  requires-current-generic-system=$requires_current_generic_system"
    echo "  requires-current-ownership-semantics=$requires_current_ownership_semantics"
    echo "  requires-current-method-resolution=$requires_current_method_resolution"
    echo "  requires-duplicate-semantic-authority=$requires_duplicate_semantic_authority"
    echo "  bounded-compatibility-layer=$bounded_compatibility_layer"
    echo
    echo "historical-root-verdict=$historical_root_verdict"
    echo
    echo "DIRECT_SEED_CLOSURE=REJECTED"
    echo "SEED_REASSIGNMENT_FIX=FORBIDDEN_BY_CURRENT_GATE"
    echo "HISTORICAL_IS_ERR_FIX=FORBIDDEN_BY_CURRENT_GATE"
    echo "MIR_TO_SSEED_ADAPTER_IMPLEMENTATION=BLOCKED_UNTIL_EXECUTOR_FRONTIER_CLASSIFIED"
} | tee "$report"

[ "$gate" = GREEN ]
