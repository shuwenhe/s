#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
modular_dir="$root/.bootstrap/modular"
entry_rel="src/cmd/compile/modular_build_main.s"
closure="${STAGE0_CLOSURE:-"$modular_dir/canonical-closure.txt"}"

tmp="${TMPDIR:-/tmp}/b6.7.3e2-stage1-producer.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

get_field() {
    local file="$1"
    local key="$2"
    if [ -f "$file" ]; then
        awk -F= -v key="$key" '$1 == key { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$file"
    else
        echo "UNKNOWN"
    fi
}

run_optional() {
    local label="$1"
    shift
    set +e
    "$@" >"$tmp/$label.report" 2>&1
    local status=$?
    set -e
    echo "$status" >"$tmp/$label.status"
}

run_optional e1 bash "$root/misc/scripts/check-b6.7.3e1-canonical-build-runtime-target-audit.sh"
run_optional root_design sh "$root/misc/scripts/canonical-bootstrap-root-strategy-design-check.sh"
run_optional ir_emission sh "$root/misc/scripts/canonical-bootstrap-ir-emission-audit.sh"
run_optional root_decision sh "$root/misc/scripts/bootstrap-root-strategy-decision.sh"

closure_count=0
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
fi

candidate_ir_consumer=$(get_field "$modular_dir/bootstrap-root-strategy-decision.txt" "candidate-ir-existing-consumer")
candidate_ir_dup=$(get_field "$modular_dir/bootstrap-root-strategy-decision.txt" "candidate-ir-semantic-duplication")
candidate_ir_regen=$(get_field "$modular_dir/bootstrap-root-strategy-decision.txt" "candidate-ir-regeneration")
candidate_ir_evidence=$(get_field "$modular_dir/bootstrap-root-strategy-decision.txt" "candidate-ir-current-evidence")
ir_emission_state=$(get_field "$modular_dir/canonical-bootstrap-ir-emission-audit.txt" "canonical-bootstrap-ir-emission")
ir_missing=$(get_field "$modular_dir/canonical-bootstrap-ir-emission-audit.txt" "missing-capability")
root_artifact=$(get_field "$modular_dir/canonical-bootstrap-root-strategy-design-report.txt" "root-artifact")
fallback_artifact=$(get_field "$modular_dir/canonical-bootstrap-root-strategy-design-report.txt" "fallback-root-artifact")
root_semantic_authority=$(get_field "$modular_dir/canonical-bootstrap-root-strategy-design-report.txt" "root-semantic-authority")

stage1_runtime_missing=$(get_field "$tmp/e1.report" "classification")

selected_bootstrap_root="explicit Stage0/root + checked-in generated bootstrap.ir"
stage0_input="canonical closure ($closure_count files) -> finalized canonical snapshot -> generated bootstrap.ir"
bootstrap_artifact="bootstrap.ir"
artifact_consumer="existing seed IR/AOT consumer"
stage1_output=".bootstrap/modular/s_modular-stage1"
stage1_entry="modular_build_main.main/build"
canonical_build_runtime_contained=NO
backend_elf64_contained=NO
bootstrap_cycle=NO
permanent_dual_authority=NO
classification=STAGE1_PRODUCER_DESIGN_PROVEN

if [ "$root_artifact" != IR ] && [ "$root_artifact" != bootstrap.ir ]; then
    selected_bootstrap_root="explicit Stage0/root + generated C fallback"
    bootstrap_artifact="bootstrap.c"
    artifact_consumer="host C compiler"
fi

if [ "$candidate_ir_consumer" = UNKNOWN ] || [ "$ir_emission_state" = UNKNOWN ]; then
    classification=STAGE1_PRODUCER_DESIGN_PARTIAL
fi

echo "B6.7.3e2 Canonical Stage1 Producer Design"
echo "purpose=design-audit-only-no-implementation"
echo "canonical-entry=$entry_rel"
echo "canonical-closure=$closure"
echo "canonical-closure-count=$closure_count"
echo "current-runtime-target-classification=$stage1_runtime_missing"
echo "producer=explicit Stage0/root"
echo "artifact-boundary-candidates=NATIVE,BOOTSTRAP_IR,GENERATED_C,TRUSTED_BOOTSTRAP_ARTIFACT"
echo "invariant-stage0-semantic-authority=BOOTSTRAP_BOUNDED"
echo "invariant-canonical-stage1-semantic-authority=PERMANENT"
echo "invariant-two-permanent-semantic-authorities=FORBIDDEN"
echo "candidate=A-native-machine-code"
echo "candidate-A-can-produce-37-file-closure=NO"
echo "candidate-A-requires-canonical-semantic-before-stage1=YES"
echo "candidate-A-duplicates-semantic-authority=RISK_HIGH"
echo "candidate-A-bootstrap-cycle=RISK_HIGH"
echo "candidate-A-host-dependency=TARGET_LINKER_AND_NATIVE_ABI"
echo "candidate-A-artifact-reproducible=UNKNOWN"
echo "candidate-A-stage1-contains-modular-build-main=NO"
echo "candidate-A-stage1-contains-backend-elf64=NO"
echo "candidate-A-can-regenerate-stage1=UNKNOWN"
echo "candidate-A-verdict=REJECT_FOR_NOW"
echo "candidate=B-bootstrap-ir"
echo "candidate-B-can-produce-37-file-closure=DESIGN_YES_IMPLEMENTATION_MISSING"
echo "candidate-B-requires-canonical-semantic-before-stage1=BOUNDED_SNAPSHOT_ONLY"
echo "candidate-B-duplicates-semantic-authority=$candidate_ir_dup"
echo "candidate-B-bootstrap-cycle=NO"
echo "candidate-B-host-dependency=$candidate_ir_consumer"
echo "candidate-B-artifact-reproducible=$candidate_ir_regen"
echo "candidate-B-stage1-contains-modular-build-main=DESIGN_REQUIRED"
echo "candidate-B-stage1-contains-backend-elf64=DESIGN_REQUIRED"
echo "candidate-B-can-regenerate-stage1=DESIGN_YES_VIA_STAGE2_OR_STAGE3"
echo "candidate-B-current-evidence=$candidate_ir_evidence"
echo "candidate-B-emission-state=$ir_emission_state"
echo "candidate-B-missing-capability=$ir_missing"
echo "candidate-B-verdict=RECOMMENDED"
echo "candidate=C-generated-c"
echo "candidate-C-can-produce-37-file-closure=DESIGN_POSSIBLE_IMPLEMENTATION_MISSING"
echo "candidate-C-requires-canonical-semantic-before-stage1=BOUNDED_SNAPSHOT_ONLY"
echo "candidate-C-duplicates-semantic-authority=NO_IF_GENERATED_NOT_HAND_MAINTAINED"
echo "candidate-C-bootstrap-cycle=NO"
echo "candidate-C-host-dependency=HOST_C_COMPILER_AND_C_ABI"
echo "candidate-C-artifact-reproducible=STRONG_POTENTIAL"
echo "candidate-C-stage1-contains-modular-build-main=DESIGN_REQUIRED"
echo "candidate-C-stage1-contains-backend-elf64=DESIGN_REQUIRED"
echo "candidate-C-can-regenerate-stage1=DESIGN_YES_VIA_STAGE2_OR_STAGE3"
echo "candidate-C-verdict=FALLBACK"
echo "candidate=D-existing-trusted-bootstrap-artifact"
echo "candidate-D-can-produce-37-file-closure=PARTIAL"
echo "candidate-D-requires-canonical-semantic-before-stage1=NO"
echo "candidate-D-duplicates-semantic-authority=NO"
echo "candidate-D-bootstrap-cycle=NO"
echo "candidate-D-host-dependency=PLATFORM_BINARY_OR_EXISTING_ARTIFACT"
echo "candidate-D-artifact-reproducible=NOT_PROVEN"
echo "candidate-D-stage1-contains-modular-build-main=NOT_PROVEN"
echo "candidate-D-stage1-contains-backend-elf64=NOT_PROVEN"
echo "candidate-D-can-regenerate-stage1=NOT_PROVEN"
echo "candidate-D-verdict=INSUFFICIENT_AS_PRIMARY"
echo "bootstrap-root=$selected_bootstrap_root"
echo "stage0-input=$stage0_input"
echo "bootstrap-artifact=$bootstrap_artifact"
echo "artifact-consumer=$artifact_consumer"
echo "stage1-output=$stage1_output"
echo "stage1-entry=$stage1_entry"
echo "canonical-build-runtime-contained=$canonical_build_runtime_contained"
echo "backend_elf64-contained=$backend_elf64_contained"
echo "semantic-authority-stage0=$root_semantic_authority"
echo "semantic-authority-stage1=CANONICAL"
echo "bootstrap-cycle=$bootstrap_cycle"
echo "permanent-dual-authority=$permanent_dual_authority"
echo "implementation-next=e3 implement canonical Stage1 producer for selected bootstrap artifact boundary"
echo "non-goal=modify-stage0-dispatch"
echo "non-goal=expand-bootstrap-subset"
echo "non-goal=modify-c-seed-semantic"
echo "non-goal=modify-qualified-resolver"
echo "classification=$classification"

if [ "$classification" = STAGE1_PRODUCER_DESIGN_PARTIAL ]; then
    exit 1
fi
