#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${CANONICAL_DROP_LOWERING_INTEGRATION_AUDIT_REPORT:-"$root/.bootstrap/modular/canonical-drop-lowering-integration-audit.txt"}

mkdir -p "$(dirname -- "$report")"

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

drop_authority=UNKNOWN
if has_text 'type_needs_drop|requires_drop|drop_decision|drop_flag|mir_statement::drop|mir_statement.drop' src/cmd/compile/internal; then
    drop_authority=CANONICAL_OWNERSHIP_DROP_INFRASTRUCTURE
fi

drop_record_created=NO
if has_text 'mir_drop_stmt' src/cmd/compile/internal || \
   has_text 'dropmap version=1' src/cmd/compile/internal || \
   has_text 'drop_summary' src/cmd/compile/internal || \
   has_text 'drop_call' src/cmd/compile/internal || \
   has_text 'Drop\(' misc/scripts src/cmd/compile/internal; then
    drop_record_created=YES
fi

drop_record_populated=NO
if has_text 'mir_statement::drop|mir_statement.drop|build_drop_metadata_artifact|drop_flag_drop|drop_flag_cleanup_names|drop_decision' src/cmd/compile/internal; then
    drop_record_populated=PARTIAL
fi

drop_record_consumed=NO
if has_text 'validate_drop_contract_chain|compile.*drop|execute_mir_statement.*drop|emit.*drop' src/cmd/compile/internal; then
    drop_record_consumed=PARTIAL
fi

drop_decisions_final_before_snapshot=UNKNOWN
if has_text 'emit-mir-after-drop|emit-mir-partial-drop|check-mir-drop-elaboration|check-mir-partial-drop' misc/scripts; then
    drop_decisions_final_before_snapshot=PARTIAL
fi

serializer_would_need_drop_semantics=UNKNOWN
verdict=DROP_INTEGRATION_MISSING
if [ "$drop_record_created" = YES ] && [ "$drop_record_populated" = YES ] && \
   [ "$drop_record_consumed" = YES ] && [ "$drop_decisions_final_before_snapshot" = YES ]; then
    serializer_would_need_drop_semantics=NO
    verdict=DROP_SNAPSHOT_READY
elif [ "$drop_authority" = CANONICAL_OWNERSHIP_DROP_INFRASTRUCTURE ]; then
    serializer_would_need_drop_semantics=UNKNOWN
    verdict=DROP_INTEGRATION_MISSING
else
    serializer_would_need_drop_semantics=YES
    verdict=DROP_AUTHORITY_NOT_PROVEN
fi

{
    echo "canonical-drop-lowering-integration-audit"
    echo "purpose=read-only-drop-snapshot-authority-audit"
    echo "drop-authority=$drop_authority"
    echo "drop-record-created=$drop_record_created"
    echo "drop-record-populated=$drop_record_populated"
    echo "drop-record-consumed=$drop_record_consumed"
    echo "drop-decisions-final-before-snapshot=$drop_decisions_final_before_snapshot"
    echo "serializer-would-need-drop-semantics=$serializer_would_need_drop_semantics"
    echo "snapshot-boundary=candidate-lowered-state"
    echo "drop-infrastructure=EXISTS"
    echo "drop-integration=NOT_PROVEN"
    echo "hard-fuse=serializer-would-need-drop-semantics=YES"
    echo "non-goal=implement-drop-lowering"
    echo "non-goal=implement-bootstrap-ir-serializer"
    echo "verdict=$verdict"
} >"$report"

cat "$report"

exit 0
