#!/usr/bin/env bash
set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
report="${P05D5A_REPORT:-$root/.bootstrap/modular/p0.5d5a-call-return-bind-authority.txt}"
spec=doc/p0.5d5a-call-return-bind-authority.md
expected=17df24ba79f4d818a994d66608f8deb61848ae54ebda339c1204f11f22fcd8f2
tmp=$(mktemp -d "${TMPDIR:-/tmp}/s-p05d5a.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cd "$root"
publish() {
    mkdir -p "$(dirname "$report")"
    cp "$tmp/report" "$report"
    cat "$report"
}
invalid() {
    printf '%s\n' 'P0_5D_5A_CALL_RETURN_BIND_AUTHORITY=RED' \
        'classification=NOT_PROVEN' "validation-error=$1" \
        'implementation=BLOCKED' 'snapshot-generation=BLOCKED' >"$tmp/report"
    publish
    exit 2
}
check=misc/scripts/check-p0.5d3-first-snapshot-producer-selection.sh
test -f "$check" || invalid MISSING_SOURCE_BINDING_CHECK
prior_rc=0
S_ROOT="$root" P05D3_REPORT="$tmp/binding" bash "$check" >"$tmp/prior.log" 2>&1 || prior_rc=$?
test "$prior_rc" = 1 && test -f "$tmp/binding" || invalid SOURCE_OR_PRIOR_EVIDENCE_INVALID
grep -qx 'source-binding=MATCH' "$tmp/binding" || invalid SOURCE_BINDING_MISMATCH
grep -qx "canonical-source-hash=$expected" "$tmp/binding" || invalid UNEXPECTED_SOURCE_HASH
test -f "$spec" || invalid MISSING_AUDIT_DOCUMENT

evidence=(
    src/s/parser.s
    src/cmd/compile/modular_build_main.s
    src/cmd/compile/internal/semantic.s
    src/cmd/compile/internal/ir/lower.s
    src/cmd/compile/internal/mir.s
    src/cmd/compile/internal/ssa_core.s
    src/cmd/compile/internal/backend_elf64.s
    src/cmd/compile/internal/tests/test_pipeline_regression.s
    src/cmd/compile/seed/intermediate/ir.c
    src/cmd/compile/seed/code/generator.c
    src/cmd/compile/seed/code/standalone_amd64_backend.c
    src/cmd/compile/seed/runtime/runtime.c
    src/cmd/compile/internal/backend/instruction_select.s
    src/cmd/compile/internal/backend/instruction_selector.s
    src/cmd/compile/internal/backend/codegen_x86_64.s
    src/cmd/compile/internal/ir/ir_builder.s
    src/cmd/compile/internal/ssa/expand_calls.s
)
for path in "${evidence[@]}"; do
    test -f "$path" || invalid MISSING_EVIDENCE
done

# Source binding proves the reviewed canonical bytes; the classification is a
# static audit decision, not an executable test inferred from CALL keywords.
{
    printf '%s\n' 'P0_5D_5A_CALL_RETURN_BIND_AUTHORITY=RED' \
        'MODE=AUDIT_DESIGN_ONLY' 'audit-status=AUTHORITY_TRACE_COMPLETE_FOR_PROBE' \
        "canonical-source-hash=$expected" 'source-binding=MATCH' \
        'probe=args := std.env.args()' 'source-call=PROVEN' \
        'evidence-kind=STATIC_SOURCE_INSPECTION_NOT_EXECUTION' \
        'call-lowering-authority=NONE_FOR_EXECUTABLE_PROBE' \
        'return-value-authority=NONE_FOR_LOWERED_CALL_RESULT' \
        'result-binding-authority=NONE_FOR_LOWERED_INITIALIZER' \
        'authority-production-reachable=NO' \
        'backend-call-consumer=seed standalone emit_function; seed runtime CALL handler' \
        'backend-call-consumer-role=NON_CANONICAL_CONSUMER_ONLY' \
        'classification=CANONICAL_CAPABILITY_GAP' \
        'classification-scope=FROZEN_37_FILE_CLOSURE_AND_AUDITED_BUILD_ROUTE' \
        'FIRST_MISSING_EDGE=SOURCE_CALL_INITIALIZER_TO_EXECUTABLE_CALL_RESULT_AND_LOCAL_BINDING' \
        'ir-ast-call=EXISTS_WITHOUT_EXECUTABLE_CONSUMER_CHAIN' \
        'ir-ast-production-reachable=NO_ON_BUILD_ROUTE_TEST_BRANCH_ONLY' \
        'mir-call-producer=NONE_FOR_PROBE' 'ssa-call-producer=NONE_FOR_PROBE' \
        'ssa-call-markers=COUNTS_NOT_EXECUTABLE_OPERANDS' \
        'ssa-entry-symbol-binding=NOT_PROVEN' \
        'interpreter-call-return-bind=EXISTS_AS_AST_EXECUTION_NOT_LOWERING' \
        'interpreter-probe-support=NOT_PROVEN' \
        'seed-call-return-bind=EXISTS_OUTSIDE_CANONICAL_AUTHORITY' \
        'outside-closure-helpers=REFERENCE_ONLY' \
        'implementation=BLOCKED' 'snapshot-generation=BLOCKED' \
        "representation-authority-matrix=$spec" '[evidence-sha256]'
    shasum -a 256 .bootstrap/modular/canonical-closure.freeze.manifest "$spec" "$check" "${evidence[@]}"
} >"$tmp/report"
publish
exit 1
