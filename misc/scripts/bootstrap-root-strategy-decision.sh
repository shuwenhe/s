#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${BOOTSTRAP_ROOT_STRATEGY_DECISION_REPORT:-"$root/.bootstrap/modular/bootstrap-root-strategy-decision.txt"}
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

ir_feasibility="$modular_dir/canonical-bootstrap-ir-feasibility-probe.txt"
ir_slice="$modular_dir/canonical-bootstrap-ir-representative-slice-probe.txt"
ir_emission="$modular_dir/canonical-bootstrap-ir-emission-audit.txt"
drop_completion="$modular_dir/canonical-drop-authority-completion-audit.txt"
symbol_requirements="$modular_dir/canonical-symbol-bootstrap-requirements-audit.txt"
strategy_design="$modular_dir/canonical-bootstrap-root-strategy-design-report.txt"
thin_bridge="$modular_dir/canonical-bootstrap-p1-transport-probe.txt"

ir_consumer_verdict=$(get_field "$ir_feasibility" "probe-verdict")
ir_slice_verdict=$(get_field "$ir_slice" "probe-verdict")
ir_emission_verdict=$(get_field "$ir_emission" "canonical-bootstrap-ir-emission")
drop_verdict=$(get_field "$drop_completion" "verdict")
drop_serializer_semantics=$(get_field "$drop_completion" "serializer-needs-ownership-analysis")
symbol_verdict=$(get_field "$symbol_requirements" "verdict")
root_strategy=$(get_field "$strategy_design" "root-strategy")
thin_bridge_verdict=$(get_field "$thin_bridge" "probe-verdict")

ir_evidence_score=0
ir_consumer_evidence=NO
ir_slice_evidence=NO
ir_emission_evidence=NO
ir_drop_evidence=NO
ir_symbol_evidence=NO
if [ "$ir_consumer_verdict" = IR_ROOT_PARTIAL ] || [ "$ir_consumer_verdict" = IR_ROOT_FEASIBLE ]; then
    ir_consumer_evidence=YES
    ir_evidence_score=$((ir_evidence_score + 1))
fi
if [ "$ir_slice_verdict" = IR_REPRESENTATION_PROVEN ] || [ "$ir_slice_verdict" = CANONICAL_IR_SLICE_PROVEN ]; then
    ir_slice_evidence=YES
    ir_evidence_score=$((ir_evidence_score + 1))
fi
if [ "$ir_emission_verdict" = ADAPTER_FEASIBLE ] || [ "$ir_emission_verdict" = EXISTING ]; then
    ir_emission_evidence=YES
    ir_evidence_score=$((ir_evidence_score + 1))
fi
if [ "$drop_verdict" = DROP_DECISIONS_FINAL_REPRESENTATION_MISSING ] && [ "$drop_serializer_semantics" = NO ]; then
    ir_drop_evidence=YES
    ir_evidence_score=$((ir_evidence_score + 1))
fi
if [ "$symbol_verdict" = SYMBOL_BOOTSTRAP_REQUIREMENTS_SUFFICIENT ]; then
    ir_symbol_evidence=YES
    ir_evidence_score=$((ir_evidence_score + 1))
fi

selected_root_strategy=UNDECIDED
decision=NEEDS_MORE_EVIDENCE
if [ "$ir_evidence_score" -ge 5 ] && [ "$root_strategy" = BOUNDED ]; then
    selected_root_strategy=GENERATED_BOOTSTRAP_IR
    decision=BOOTSTRAP_IR_SELECTED
fi

{
    echo "bootstrap-root-strategy-decision"
    echo "purpose=architecture-decision-record-no-implementation"
    echo "B3-feasibility-investigation=CLOSED"
    echo "candidate-set=GENERATED_BOOTSTRAP_IR,GENERATED_C_BOOTSTRAP_ARTIFACT,PREBUILT_TRUSTED_BINARY"
    echo "excluded-candidate=SOURCE_LEVEL_THIN_BRIDGE"
    echo "excluded-reason=thin-bridge-semantic-gap-triggered"
    echo "thin-bridge-prior-verdict=$thin_bridge_verdict"
    echo "decision-principle=bootstrap-root-semantic-authority-allowed-if-bounded"
    echo "decision-principle=thin-bridge-semantic-authority-forbidden"
    echo "decision-principle=long-term-dual-semantic-authority-forbidden"
    echo "candidate=Generated Bootstrap IR"
    echo "candidate-ir-non-circular=YES"
    echo "candidate-ir-canonical-authority=STRONG"
    echo "candidate-ir-reviewability=STRONG"
    echo "candidate-ir-reproducibility=STRONG_POTENTIAL"
    echo "candidate-ir-existing-consumer=PROVEN"
    echo "candidate-ir-host-dependency=existing-seed-ir-aot"
    echo "candidate-ir-semantic-duplication=NO"
    echo "candidate-ir-cross-platform-potential=STRONG"
    echo "candidate-ir-regeneration=STRONG_POTENTIAL"
    echo "candidate-ir-current-evidence=STRONGEST"
    echo "candidate-ir-consumer-verdict=$ir_consumer_verdict"
    echo "candidate-ir-slice-verdict=$ir_slice_verdict"
    echo "candidate-ir-emission-state=$ir_emission_verdict"
    echo "candidate-ir-drop-verdict=$drop_verdict"
    echo "candidate-ir-symbol-verdict=$symbol_verdict"
    echo "candidate-ir-evidence-consumer=$ir_consumer_evidence"
    echo "candidate-ir-evidence-slice=$ir_slice_evidence"
    echo "candidate-ir-evidence-emission=$ir_emission_evidence"
    echo "candidate-ir-evidence-drop=$ir_drop_evidence"
    echo "candidate-ir-evidence-symbol=$ir_symbol_evidence"
    echo "candidate-ir-evidence-score=$ir_evidence_score/5"
    echo "root-strategy-design=$root_strategy"
    echo "candidate-ir-remaining-implementation=snapshot-contract-plus-structural-adapter-serializer"
    echo "candidate=Generated C Bootstrap Artifact"
    echo "candidate-c-non-circular=YES"
    echo "candidate-c-canonical-authority=STRONG_IF_GENERATED_FROM_CANONICAL"
    echo "candidate-c-reviewability=MEDIUM_STRONG"
    echo "candidate-c-reproducibility=STRONG_POTENTIAL"
    echo "candidate-c-existing-consumer=HOST_C_COMPILER_REQUIRES_CONFIRMATION"
    echo "candidate-c-host-dependency=C_COMPILER_AND_C_ABI"
    echo "candidate-c-semantic-duplication=NO_IF_GENERATED_NOT_HAND_MAINTAINED"
    echo "candidate-c-cross-platform-potential=STRONG_WITH_HOST_C_VARIANCE"
    echo "candidate-c-regeneration=STRONG_POTENTIAL"
    echo "candidate-c-current-evidence=FALLBACK"
    echo "candidate=Prebuilt Trusted Binary"
    echo "candidate-binary-non-circular=YES"
    echo "candidate-binary-canonical-authority=MEDIUM"
    echo "candidate-binary-reviewability=WEAK"
    echo "candidate-binary-reproducibility=WEAK_TO_MEDIUM"
    echo "candidate-binary-existing-consumer=OS_LOADER"
    echo "candidate-binary-host-dependency=PLATFORM_BINARY"
    echo "candidate-binary-semantic-duplication=NO"
    echo "candidate-binary-cross-platform-potential=WEAK"
    echo "candidate-binary-regeneration=POSSIBLE_BUT_COMPLEX"
    echo "candidate-binary-current-evidence=FALLBACK"
    echo "selected-root-strategy=$selected_root_strategy"
    echo "preferred-strategy=$selected_root_strategy"
    echo "trust-anchor=CHECKED_IN_GENERATED_IR"
    echo "root-artifact=bootstrap.ir"
    echo "root-semantic-authority=BOUNDED_CANONICAL_SNAPSHOT"
    echo "root-authority-scope=STAGE1_CREATION_ONLY"
    echo "runtime-authority-after-stage1=NONE"
    echo "stage1-authority=CANONICAL"
    echo "stage2-authority=CANONICAL"
    echo "stage3-authority=CANONICAL"
    echo "fallback=GENERATED_C"
    echo "rejected=SOURCE_LEVEL_THIN_BRIDGE"
    echo "verification-required=semantic-equivalence"
    echo "verification-required=deterministic-serialization"
    echo "verification-required=artifact-equivalence-after-normalization"
    echo "verification-required=stage2-stage3-convergence"
    echo "mandatory-final-gate=canonical-selfhost-convergence-check"
    echo "next=B5-bootstrap-ir-snapshot-serialization-contract"
    echo "non-goal=write-serializer"
    echo "non-goal=write-snapshot"
    echo "non-goal=generate-full-37-file-ir"
    echo "non-goal=modify-seed-semantics"
    echo "non-goal=modify-ownership-drop"
    echo "non-goal=stage1-authority-handoff"
    echo "decision=$decision"
} >"$report"

cat "$report"

if [ "$decision" = BOOTSTRAP_IR_SELECTED ]; then
    exit 0
fi

exit 1
