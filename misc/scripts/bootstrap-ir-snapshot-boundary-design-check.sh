#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${BOOTSTRAP_IR_SNAPSHOT_BOUNDARY_REPORT:-"$root/.bootstrap/modular/bootstrap-ir-snapshot-boundary-design-check.txt"}
modular_dir="$root/.bootstrap/modular"

mkdir -p "$(dirname -- "$report")"

get_field() {
    file=$1
    key=$2
    if [ -f "$file" ]; then
        awk -F= -v key="$key" '$1 == key { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$file"
    else
        echo "UNKNOWN"
    fi
}

decision=$(get_field "$modular_dir/bootstrap-root-strategy-decision.txt" "decision")
selected_root=$(get_field "$modular_dir/bootstrap-root-strategy-decision.txt" "selected-root-strategy")
ir_emission=$(get_field "$modular_dir/canonical-bootstrap-ir-emission-audit.txt" "canonical-bootstrap-ir-emission")
drop_verdict=$(get_field "$modular_dir/canonical-drop-authority-completion-audit.txt" "verdict")
drop_serializer_semantics=$(get_field "$modular_dir/canonical-drop-authority-completion-audit.txt" "serializer-needs-ownership-analysis")
symbol_sufficient=$(get_field "$modular_dir/canonical-symbol-bootstrap-requirements-audit.txt" "symbol-state-sufficient")

contract_status=NOT_READY
if [ "$decision" = BOOTSTRAP_IR_SELECTED ] && \
   [ "$selected_root" = GENERATED_BOOTSTRAP_IR ] && \
   [ "$ir_emission" = ADAPTER_FEASIBLE ] && \
   [ "$drop_verdict" = DROP_DECISIONS_FINAL_REPRESENTATION_MISSING ] && \
   [ "$drop_serializer_semantics" = NO ] && \
   [ "$symbol_sufficient" = YES ]; then
    contract_status=BOUNDARY_DEFINED
fi

{
    echo "bootstrap-ir-snapshot-boundary-design-check"
    echo "purpose=B5.1-design-only-no-serializer"
    echo "root-decision=$decision"
    echo "selected-root-strategy=$selected_root"
    echo "snapshot-input=CANONICAL_LOWERED_STATE"
    echo "snapshot-after-semantic=REQUIRED"
    echo "snapshot-after-mono=REQUIRED"
    echo "snapshot-after-ownership-nll=REQUIRED"
    echo "snapshot-after-drop-finalization=REQUIRED"
    echo "snapshot-after-layout-finalization=REQUIRED"
    echo "snapshot-after-abi-finalization=REQUIRED"
    echo "snapshot-after-symbol-identity-resolution=REQUIRED"
    echo "snapshot-before-bootstrap-ir-serialization=REQUIRED"
    echo "snapshot-before-machine-code-emission=REQUIRED"
    echo "snapshot-before-final-address-assignment=ALLOWED"
    echo "snapshot-semantic-authority=NONE"
    echo "snapshot-mono-authority=NONE"
    echo "snapshot-ownership-authority=NONE"
    echo "snapshot-drop-authority=NONE"
    echo "snapshot-layout-authority=NONE"
    echo "snapshot-abi-authority=NONE"
    echo "snapshot-symbol-resolution-authority=NONE"
    echo "serializer-input-authority=READ_FINALIZED_CANONICAL_STATE_ONLY"
    echo "serializer-authority=REPRESENTATION_ONLY"
    echo "drop-evidence=$drop_verdict"
    echo "serializer-needs-ownership-analysis=$drop_serializer_semantics"
    echo "symbol-state-sufficient=$symbol_sufficient"
    echo "canonical-bootstrap-ir-emission=$ir_emission"
    echo "boundary-contract-status=$contract_status"
    echo "next=B5.2-serialization-format-contract"
    echo "non-goal=write-serializer"
    echo "non-goal=write-snapshot"
    echo "non-goal=generate-bootstrap-ir"
    echo "non-goal=stage1-authority-handoff"
    echo "non-goal=define-full-artifact-schema"
    if [ "$contract_status" = BOUNDARY_DEFINED ]; then
        echo "verdict=SNAPSHOT_BOUNDARY_CONTRACT_DEFINED"
    else
        echo "verdict=SNAPSHOT_BOUNDARY_CONTRACT_BLOCKED"
    fi
} >"$report"

cat "$report"

if [ "$contract_status" = BOUNDARY_DEFINED ]; then
    exit 0
fi

exit 1
