#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${CANONICAL_DROP_AUTHORITY_COMPLETION_AUDIT_REPORT:-"$root/.bootstrap/modular/canonical-drop-authority-completion-audit.txt"}

mkdir -p "$(dirname -- "$report")"

work=${TMPDIR:-/tmp}/canonical-drop-authority-completion.$$
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT HUP INT TERM

run_gate() {
    name=$1
    script=$2
    log="$work/$name.log"
    set +e
    "$root/$script" >"$log" 2>&1
    status=$?
    set -e
    if [ "$status" -eq 0 ]; then
        echo PASS
    else
        echo FAIL
    fi
}

has_text() {
    pattern=$1
    shift
    for path in "$@"; do
        if rg -q "$pattern" "$root/$path" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

drop_elaboration_gate=$(run_gate mir-drop-elaboration misc/scripts/check-mir-drop-elaboration.sh)
partial_drop_gate=$(run_gate mir-partial-drop misc/scripts/check-mir-partial-drop.sh)
nll_ownership_gate=UNKNOWN
if [ -x "$root/misc/scripts/check-mir-nll-ownership.sh" ]; then
    nll_ownership_gate=$(run_gate mir-nll-ownership misc/scripts/check-mir-nll-ownership.sh)
fi

drop_decision_producer=UNKNOWN
if has_text 'compiler_emit_mir.*drop|mir_append_scope_drops|drop_decision|drop_flag_cleanup_names' src/cmd/compile/compiler.s src/cmd/compile/internal; then
    drop_decision_producer=CANONICAL_MIR_DROP_PATH
fi

drop_decision_input=UNKNOWN
if has_text 'moved|dropped|drop_state|partial move|ownership|borrow|events' src/cmd/compile/compiler.s src/cmd/compile/internal; then
    drop_decision_input=OWNERSHIP_MOVE_BORROW_STATE
fi

drop_decision_point=UNKNOWN
if has_text 'emit-mir-after-drop|emit-mir-partial-drop|mir_append_scope_drops|compiler_emit_mir_partial_drop' misc/scripts src/cmd/compile/compiler.s src/cmd/compile/internal; then
    drop_decision_point=POST_MIR_DROP_ELABORATION_BEFORE_BOOTSTRAP_SNAPSHOT
fi

drop_record_population_authority=UNKNOWN
if has_text 'mir_statement::drop|Drop\\(|compiler_emit_mir_partial_drop|mir_append_scope_drops' src/cmd/compile/compiler.s src/cmd/compile/internal; then
    drop_record_population_authority=CANONICAL_DROP_ELABORATION
fi

drop_record_consumption_authority=UNKNOWN
if has_text 'emit-mir-after-drop|emit-mir-partial-drop|validate_drop_contract_chain|Drop\\(' misc/scripts src/cmd/compile/internal src/cmd/compile/compiler.s; then
    drop_record_consumption_authority=CANONICAL_MIR_OR_BACKEND_ARTIFACT_PATH
fi

normal_exit_drop_finalized=UNKNOWN
moved_drop_finalized=UNKNOWN
borrowed_owner_drop_finalized=UNKNOWN
early_return_drop_finalized=UNKNOWN
branch_merge_drop_finalized=UNKNOWN
lifo_drop_order_finalized=UNKNOWN
partial_move_drop_finalized=UNKNOWN
reinit_drop_finalized=UNKNOWN
nested_partial_drop_finalized=UNKNOWN

if [ "$drop_elaboration_gate" = PASS ]; then
    normal_exit_drop_finalized=YES
    moved_drop_finalized=YES
    borrowed_owner_drop_finalized=YES
    early_return_drop_finalized=YES
    branch_merge_drop_finalized=YES
    lifo_drop_order_finalized=YES
fi

if [ "$partial_drop_gate" = PASS ]; then
    partial_move_drop_finalized=YES
    reinit_drop_finalized=YES
    nested_partial_drop_finalized=YES
fi

snapshot_contains_final_drop_actions=UNKNOWN
serializer_needs_ownership_analysis=UNKNOWN
verdict=DROP_CANONICAL_LOWERING_INCOMPLETE

if [ "$normal_exit_drop_finalized" = YES ] && \
   [ "$early_return_drop_finalized" = YES ] && \
   [ "$branch_merge_drop_finalized" = YES ] && \
   [ "$partial_move_drop_finalized" = YES ] && \
   [ "$reinit_drop_finalized" = YES ] && \
   [ "$nested_partial_drop_finalized" = YES ] && \
   [ "$drop_record_population_authority" = CANONICAL_DROP_ELABORATION ]; then
    snapshot_contains_final_drop_actions=YES
    serializer_needs_ownership_analysis=NO
    verdict=DROP_DECISIONS_FINAL_REPRESENTATION_MISSING
fi

if [ "$drop_elaboration_gate" = FAIL ] || [ "$partial_drop_gate" = FAIL ]; then
    snapshot_contains_final_drop_actions=NO
    serializer_needs_ownership_analysis=YES
    verdict=DROP_CANONICAL_LOWERING_INCOMPLETE
fi

{
    echo "canonical-drop-authority-completion-audit"
    echo "purpose=read-only-drop-authority-completion-audit"
    echo "drop-decision-producer=$drop_decision_producer"
    echo "drop-decision-input=$drop_decision_input"
    echo "drop-decision-point=$drop_decision_point"
    echo "drop-record-population-authority=$drop_record_population_authority"
    echo "drop-record-consumption-authority=$drop_record_consumption_authority"
    echo "evidence-gate=mir-drop-elaboration:$drop_elaboration_gate"
    echo "evidence-gate=mir-partial-drop:$partial_drop_gate"
    echo "evidence-gate=mir-nll-ownership:$nll_ownership_gate"
    echo "normal-exit-drop-finalized=$normal_exit_drop_finalized"
    echo "moved-drop-finalized=$moved_drop_finalized"
    echo "borrowed-owner-drop-finalized=$borrowed_owner_drop_finalized"
    echo "early-return-drop-finalized=$early_return_drop_finalized"
    echo "branch-merge-drop-finalized=$branch_merge_drop_finalized"
    echo "lifo-drop-order-finalized=$lifo_drop_order_finalized"
    echo "partial-move-drop-finalized=$partial_move_drop_finalized"
    echo "reinit-drop-finalized=$reinit_drop_finalized"
    echo "nested-partial-drop-finalized=$nested_partial_drop_finalized"
    echo "snapshot-contains-final-drop-actions=$snapshot_contains_final_drop_actions"
    echo "serializer-needs-ownership-analysis=$serializer_needs_ownership_analysis"
    echo "serializer-semantic-authority=NONE"
    echo "non-goal=implement-drop-integration"
    echo "non-goal=implement-bootstrap-ir-serializer"
    echo "verdict=$verdict"
    for log in "$work"/*.log; do
        [ -f "$log" ] || continue
        name=$(basename "$log" .log)
        if [ -s "$log" ]; then
            sed "s/^/evidence-log-$name=/" "$log"
        fi
    done
} >"$report"

cat "$report"

exit 0
