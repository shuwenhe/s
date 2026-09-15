#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${BOOTSTRAP_IR_EQUIVALENCE_REGENERATION_REPORT:-"$root/.bootstrap/modular/bootstrap-ir-equivalence-regeneration-design-check.txt"}
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

schema_verdict=$(get_field "$modular_dir/bootstrap-ir-artifact-schema-design-check.txt" "verdict")
schema_authority=$(get_field "$modular_dir/bootstrap-ir-artifact-schema-design-check.txt" "schema-decision-authority")
semantic_leak=$(get_field "$modular_dir/bootstrap-ir-artifact-schema-design-check.txt" "semantic-authority-leak")
format_verdict=$(get_field "$modular_dir/bootstrap-ir-serialization-format-design-check.txt" "verdict")
serialization_determinism=$(get_field "$modular_dir/bootstrap-ir-serialization-format-design-check.txt" "serialization-determinism")
semantic_order=$(get_field "$modular_dir/bootstrap-ir-serialization-format-design-check.txt" "semantic-order-preservation")

regeneration_contract_status=NOT_DEFINED
if [ "$schema_verdict" = BOOTSTRAP_IR_ARTIFACT_SCHEMA_DEFINED ] && \
   [ "$schema_authority" = NONE ] && \
   [ "$semantic_leak" = NO ] && \
   [ "$format_verdict" = SERIALIZATION_FORMAT_CONTRACT_DEFINED ] && \
   [ "$serialization_determinism" = REQUIRED ] && \
   [ "$semantic_order" = REQUIRED ]; then
    regeneration_contract_status=DEFINED
fi

{
    echo "bootstrap-ir-equivalence-regeneration-design-check"
    echo "purpose=B5.4-design-only-no-comparator-no-regenerator"
    echo "depends-on-schema=$schema_verdict"
    echo "depends-on-format=$format_verdict"
    echo "artifact-kind=BOOTSTRAP_IR"
    echo "format=SSEED-TARGET-V1"
    echo "format-version=1"
    echo "equivalence-level=1:SEMANTIC_EQUIVALENCE:REQUIRED"
    echo "equivalence-level=2:STRUCTURAL_EQUIVALENCE:REQUIRED"
    echo "equivalence-level=3:SERIALIZATION_EQUIVALENCE:REQUIRED"
    echo "equivalence-level=4:BYTE_IDENTITY:REQUIRED"
    echo "equivalence-strength=byte-identity-implies-canonical-serialization-implies-structural-equivalence-implies-semantic-equivalence"
    echo "required-bootstrap-artifact-equivalence=BYTE_IDENTICAL"
    echo "byte-identity-source=CANONICAL_DETERMINISTIC_SERIALIZATION"
    echo "byte-identity-by-dropping-semantic-information=FORBIDDEN"
    echo "semantic-order-preservation=REQUIRED"
    echo "determinism-must-not-change-semantics=REQUIRED"
    echo "bootstrap-root-regenerator=CANONICAL_STAGE2_OR_STAGE3"
    echo "seed-root-regeneration-authority=FORBIDDEN"
    echo "bootstrap-subset-root-regeneration-authority=FORBIDDEN"
    echo "manual-root-regeneration-authority=FORBIDDEN"
    echo "regeneration-input=CANONICAL_SOURCE_CLOSURE_PLUS_CANONICAL_STAGE2_OR_STAGE3"
    echo "regeneration-output=REGENERATED_BOOTSTRAP_IR"
    echo "checked-in-root-artifact=bootstrap.ir"
    echo "checked-in-root-role=BOOTSTRAP_TRUST_ANCHOR"
    echo "regeneration-by-seed=FORBIDDEN"
    echo "regeneration-before-stage1=FORBIDDEN"
    echo "bootstrap-chain=checked-in-bootstrap.ir -> seed-ir-aot -> stage1 -> canonical-stage2 -> canonical-stage3"
    echo "regeneration-chain=canonical-stage2-or-stage3 -> finalized-canonical-state -> deterministic-serializer -> regenerated-bootstrap.ir"
    echo "bootstrap-artifact-equivalence-gate=REQUIRED"
    echo "stage2-stage3-convergence-gate=REQUIRED"
    echo "gates-are-distinct=YES"
    echo "both-required-for-final-bootstrap-closure=YES"
    echo "bootstrap-artifact-equivalence-answers=trust-anchor-derived-from-canonical-compiler"
    echo "stage2-stage3-convergence-answers=canonical-compiler-selfhost-convergence"
    echo "stage2-stage3-convergence-does-not-imply-root-regeneration=TRUE"
    echo "root-regeneration-does-not-imply-stage2-stage3-convergence=TRUE"
    echo "failure-class=SEMANTIC_MISMATCH"
    echo "failure-class=STRUCTURAL_MISMATCH"
    echo "failure-class=NONDETERMINISTIC_SERIALIZATION"
    echo "failure-class=INCIDENTAL_METADATA_LEAK"
    echo "failure-class=IDENTITY_INSTABILITY"
    echo "failure-class=TARGET_MISMATCH"
    echo "failure-class=FORMAT_VERSION_MISMATCH"
    echo "failure-class=SCHEMA_VERSION_MISMATCH"
    echo "failure-class=SEMANTIC_ORDER_VIOLATION"
    echo "failure-policy-semantic-mismatch=FIX_CANONICAL_COMPILER_OR_SNAPSHOT_INPUT"
    echo "failure-policy-structural-mismatch=FIX_CANONICAL_STATE_OR_SCHEMA_MAPPING"
    echo "failure-policy-nondeterminism=FIX_SERIALIZER_OR_CANONICAL_IDENTITY"
    echo "failure-policy-metadata-leak=REMOVE_INCIDENTAL_METADATA"
    echo "failure-policy-identity-instability=FIX_STABLE_IDENTITY"
    echo "failure-policy-target-mismatch=REBUILD_WITH_EXPLICIT_TARGET_OR_REJECT_COMPARISON"
    echo "failure-policy-format-version-mismatch=REJECT_COMPARISON"
    echo "comparator-semantic-authority=NONE"
    echo "comparator-parser-authority=NONE"
    echo "comparator-drop-authority=NONE"
    echo "comparator-layout-authority=NONE"
    echo "comparator-abi-authority=NONE"
    echo "comparator-role=COMPARE_CANONICAL_ARTIFACTS_ONLY"
    echo "normalization-role=FORMAT_NORMALIZATION_ONLY"
    echo "normalization-semantic-rewrite=FORBIDDEN"
    echo "final-bootstrap-closure-requires=bootstrap-artifact-byte-identity"
    echo "final-bootstrap-closure-requires=stage2-stage3-semantic-equivalence"
    echo "final-bootstrap-closure-requires=stage2-stage3-artifact-convergence"
    echo "final-bootstrap-closure-requires=bootstrap-root-used-after-stage1=NO"
    echo "bootstrap-ir-contract=B5_COMPLETE_IF_DEFINED"
    echo "next=B6-minimal-canonical-bootstrap-ir-emission"
    echo "non-goal=write-equivalence-comparator"
    echo "non-goal=write-regenerator"
    echo "non-goal=write-serializer"
    echo "non-goal=generate-bootstrap-ir"
    echo "non-goal=run-stage2-stage3-convergence"
    echo "regeneration-contract-status=$regeneration_contract_status"
    if [ "$regeneration_contract_status" = DEFINED ]; then
        echo "verdict=BOOTSTRAP_IR_EQUIVALENCE_REGENERATION_CONTRACT_DEFINED"
    else
        echo "verdict=BOOTSTRAP_IR_EQUIVALENCE_REGENERATION_CONTRACT_BLOCKED"
    fi
} >"$report"

cat "$report"

if [ "$regeneration_contract_status" = DEFINED ]; then
    exit 0
fi

exit 1
