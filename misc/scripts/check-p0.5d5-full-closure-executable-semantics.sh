#!/usr/bin/env bash
set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
report="${P05D5_REPORT:-$root/.bootstrap/modular/p0.5d5-full-closure-executable-semantics.txt}"
spec=doc/p0.5d5-full-closure-executable-semantics.md
expected=17df24ba79f4d818a994d66608f8deb61848ae54ebda339c1204f11f22fcd8f2
tmp=$(mktemp -d "${TMPDIR:-/tmp}/s-p05d5.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cd "$root"

publish() {
    mkdir -p "$(dirname "$report")"
    cp "$tmp/report" "$report"
    cat "$report"
}
invalid() {
    printf '%s\n' 'P0_5D_5_FULL_CLOSURE_EXECUTABLE_SEMANTICS=RED' \
        'audit-status=INPUT_OR_EVIDENCE_INVALID' "validation-error=$1" \
        'FIRST_MISSING_EXECUTABLE_SEMANTIC_EDGE=NOT_ASSESSED' \
        'snapshot-generation=BLOCKED' >"$tmp/report"
    publish
    exit 2
}

# Validate pinned source bytes/commit without regenerating the freeze manifest.
check=misc/scripts/check-p0.5d3-first-snapshot-producer-selection.sh
test -f "$check" || invalid MISSING_SOURCE_BINDING_CHECK
prior_rc=0
S_ROOT="$root" P05D3_REPORT="$tmp/binding" bash "$check" >"$tmp/prior.log" 2>&1 || prior_rc=$?
test "$prior_rc" = 1 && test -f "$tmp/binding" || invalid SOURCE_OR_PRIOR_EVIDENCE_INVALID
grep -qx 'source-binding=MATCH' "$tmp/binding" || invalid SOURCE_BINDING_MISMATCH
grep -qx "canonical-source-hash=$expected" "$tmp/binding" || invalid UNEXPECTED_SOURCE_HASH
test -f "$spec" || invalid MISSING_AUDIT_DOCUMENT

entry=src/cmd/compile/modular_build_main.s
lower=src/cmd/compile/internal/ir/lower.s
mir=src/cmd/compile/internal/mir.s
backend=src/cmd/compile/internal/backend_elf64.s
manifest=.bootstrap/modular/canonical-closure.freeze.manifest
: >"$tmp/anchors"
anchor() {
    rg -n -F -- "$2" "$1" >"$tmp/matches" || invalid MISSING_EVIDENCE_ANCHOR
    printf 'file=%s\n' "$1" >>"$tmp/anchors"
    cat "$tmp/matches" >>"$tmp/anchors"
}
# Locators for a reviewed static deduction, not a substitute S parser.
anchor "$entry" 'args := std.env.args()'
anchor src/env/env.s '__host_args()'
anchor "$lower" 'graph := lower_function_to_mir(picked.unwrap(), const_entries)'
anchor "$lower" 'graph.trace = append(graph.trace, "package.fn " + function_decl.sig.name)'
anchor "$lower" 'stmt.let(var_stmt) : "let " + var_stmt.name'
anchor "$lower" 'op: "line", args args,'
anchor "$mir" 'mir_append_ownership_semantics_from_expr(statements, call_expr.callee.unwrap(), "")'
anchor "$backend" 'source_exec := execute_source_main(source)'
anchor "$backend" 'body_result := execute_block_in_place(function.body.unwrap(), source, env, writes, runtime)'

: >"$tmp/main-declarations"
while IFS= read -r rel; do
    rg -H -n '^func main\(' "$rel" >>"$tmp/main-declarations" || {
        rc=$?
        test "$rc" = 1 || invalid MAIN_DECLARATION_SCAN_FAILED
    }
done < <(awk '/^\[ordered-file-list\]$/ { active=1; next } /^\[/ { active=0 } active && /^file=/ { sub(/^file=/, ""); print }' "$manifest")
test "$(wc -l <"$tmp/main-declarations" | tr -d ' ')" = 1 || invalid ENTRY_REQUIRES_REVIEW

{
    printf '%s\n' 'P0_5D_5_FULL_CLOSURE_EXECUTABLE_SEMANTICS=RED' \
        'MODE=AUDIT_DESIGN_ONLY' 'audit-status=FIRST_MISSING_EDGE_LOCATED' \
        'evidence-kind=PINNED_SOURCE_STATIC_DEDUCTION' "canonical-source-hash=$expected" \
        'source-binding=MATCH' 'canonical-file-count=37' \
        'Q1-entry=cmd.main@src/cmd/compile/modular_build_main.s:19' \
        'Q1-executable-entry=NOT_PROVEN' \
        'Q2-reachability=SOURCE_BACKED_LOWER_BOUND_IN_AUDIT_DOCUMENT' \
        'Q2-complete-call-graph=NOT_PROVEN' 'Q2-complete-mono-instance-set=NOT_PROVEN' \
        'Q3-lowering-coverage=SELECTED_FUNCTION_ONLY_WITH_INCOMPLETE_STATEMENT_SEMANTICS' \
        'Q4-source-dependency=AST_CALL_EXECUTION_AND_ON_DEMAND_SOURCE_REPARSE' \
        'FIRST_MISSING_EXECUTABLE_SEMANTIC_EDGE=MAIN_ARGS_INITIALIZER_TO_EXECUTABLE_CALL_AND_RESULT' \
        'first-witness=cmd.main -> std.env.args -> __host_args' \
        'first-loss=ir.lower.dump_expr_stmt(stmt.let) -> let args' \
        'ownership-helper-restores-call=NO' \
        'SECOND_MISSING_EXECUTABLE_SEMANTIC_EDGE=REACHABLE_CALLEE_BODY_TO_EXECUTABLE_FUNCTION_GRAPH' \
        'full-closure-executable-semantics=NO_ON_INSPECTED_LOWERING_ROUTE' \
        'responsibility-owner=canonical compile.internal.ir.lower; MIR representation; backend execution' \
        'missing-work-class=SEMANTIC_LOWERING_AND_EXECUTABLE_BODY_SCHEDULING' \
        'implementation-authorized=NO' 'compiler-execution=NOT_RUN' \
        'target-runtime-mapping=BLOCKED' 'faithful-stage2-production=BLOCKED' \
        'producer-selection=BLOCKED' 'snapshot-generation=BLOCKED' \
        "audit-document=$spec" '[entry-lexical-evidence]'
    cat "$tmp/main-declarations"
    printf '%s\n' '[reviewed-source-anchors]'
    cat "$tmp/anchors"
    printf '%s\n' '[evidence-sha256]'
    shasum -a 256 "$manifest" "$spec" "$check" "$entry" "$lower" "$mir" "$backend" \
        src/env/env.s src/result/result.s src/cmd/compile/internal/mono/monomorphization.s
} >"$tmp/report"
publish
# A completed audit with disproven coverage is still a blocking gate.
exit 1
