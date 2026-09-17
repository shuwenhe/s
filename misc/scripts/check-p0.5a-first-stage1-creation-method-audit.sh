#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
report="${P05A_FIRST_STAGE1_CREATION_METHOD_REPORT:-"$root/.bootstrap/modular/p0.5a-first-stage1-creation-method-audit.txt"}"
p04_report="$root/.bootstrap/modular/p0.4-bootstrap-artifact-provenance-audit.txt"

mkdir -p "$(dirname "$report")"

has_text() {
    local pattern="$1"
    shift
    rg -q -e "$pattern" "$root/$@" 2>/dev/null
}

status_bool() {
    if "$@"; then
        echo YES
    else
        echo NO
    fi
}

read_report_field() {
    local key="$1"
    local file="$2"
    if [ -f "$file" ]; then
        awk -F= -v key="$key" '$1 ~ key { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$file"
    else
        echo UNKNOWN
    fi
}

closure_count=0
canonical_snapshot=NOT_FOUND
canonical_snapshot_hash=NONE
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if [ "$closure_count" -gt 0 ] && grep -qx 'src/cmd/compile/modular_build_main.s' "$closure"; then
        canonical_snapshot=FOUND
    fi
    tmp_hashes="${TMPDIR:-/tmp}/s-p05a-closure-hashes.$$"
    trap 'rm -f "$tmp_hashes"' EXIT HUP INT TERM
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if [ -f "$root/$rel" ]; then
            shasum -a 256 "$root/$rel" | awk -v rel="$rel" '{ print $1 "  " rel }'
        else
            printf 'MISSING  %s\n' "$rel"
        fi
    done <"$closure" >"$tmp_hashes"
    canonical_snapshot_hash=$(shasum -a 256 "$tmp_hashes" | awk '{print $1}')
fi

p04_status=$(read_report_field '^P0_4_BOOTSTRAP_ARTIFACT_PROVENANCE$' "$p04_report")
p04_artifact_recovered=$(read_report_field 'artifact-recovered' "$p04_report")

seed_aot_consumer=$(status_bool has_text 'emit_aot_from_ir_file|emit_native_from_ir_file|--emit-aot' src/cmd/compile/seed)
host_cc_available=NO
if command -v cc >/dev/null 2>&1; then
    host_cc_available=YES
fi
object_linker_available=NO
if command -v ld >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; then
    object_linker_available=YES
fi

existing_stage2_stage3_patterns=$(status_bool has_text 'stage2.*stage3|Stage2.*Stage3|cmp .*stage2.*stage3|bootstrap-convergence' makefile src/cmd/dist misc/scripts)
manifest_contract_present=NO
if [ -f "$p04_report" ] && rg -q 'accepted-artifact-manifest-contract|required-field=artifact.type|required-field=acceptance.stage2-stage3-equivalence' "$p04_report"; then
    manifest_contract_present=YES
fi

reject_reference_compiler=YES
reject_mechanical_translation=YES
reject_manual_lowered=YES
allow_trusted_build_environment=YES
allow_checked_native=YES
allow_checked_object=YES
allow_checked_generated_c=YES
allow_checked_sseed=YES

selected_creation_method=NONE
selected_artifact_level=NONE
selection_reason=NO_ACCEPTED_CREATION_INPUT_YET

# P0.5a is a design gate: it selects the first ceremony shape, not a concrete artifact.
# Prefer the smallest executor surface first, then reviewability/portability.
if [ "$object_linker_available" = YES ]; then
    selected_creation_method=ONE_TIME_TRUSTED_BUILD_ENVIRONMENT_PRODUCES_CHECKED_NATIVE_STAGE1
    selected_artifact_level=NATIVE_EXECUTABLE
    selection_reason=MINIMUM_EXECUTOR_SURFACE_OS_LOADER_AND_STRONG_STAGE2_STAGE3_EXIT_GATE
elif [ "$host_cc_available" = YES ]; then
    selected_creation_method=ONE_TIME_TRUSTED_BUILD_ENVIRONMENT_PRODUCES_CHECKED_GENERATED_C_STAGE1
    selected_artifact_level=GENERATED_C
    selection_reason=HOST_CC_AVAILABLE_AND_ARTIFACT_REVIEWABILITY_HIGHER_THAN_BINARY
elif [ "$seed_aot_consumer" = YES ]; then
    selected_creation_method=ONE_TIME_TRUSTED_BUILD_ENVIRONMENT_PRODUCES_CHECKED_SSEED_IR_STAGE1
    selected_artifact_level=SSEED_IR
    selection_reason=SEED_AOT_CONSUMER_AVAILABLE_BUT_ARTIFACT_REVIEWABILITY_LOWER_THAN_C_AND_CREATION_TOOL_MUST_NOT_PARSE_S
fi

requires_independent_s_semantics=NO
bounded=YES
reviewable=YES
one_time=YES
producer_lifetime=ONE_TIME
long_term_semantic_authority=FORBIDDEN

gate=YELLOW
if [ "$canonical_snapshot" != FOUND ]; then
    gate=RED
    selection_reason=CANONICAL_SNAPSHOT_MISSING
elif [ "$manifest_contract_present" != YES ]; then
    gate=RED
    selection_reason=P0_4_MANIFEST_CONTRACT_MISSING
elif [ "$selected_creation_method" = NONE ]; then
    gate=RED
fi

{
    echo "P0.5a FIRST_STAGE1_CREATION_METHOD_AUDIT"
    echo "P0_5A_FIRST_STAGE1_CREATION_METHOD_AUDIT=$gate"
    echo
    echo "source:"
    echo "  canonical-snapshot=$canonical_snapshot"
    echo "  canonical-snapshot-path=$closure"
    echo "  canonical-snapshot-count=$closure_count"
    echo "  source-closure-hash=$canonical_snapshot_hash"
    echo "  p0.4-status=$p04_status"
    echo "  p0.4-artifact-recovered=$p04_artifact_recovered"
    echo
    echo "creation-contract:"
    echo "  creation-authority-lifetime=ONE_TIME"
    echo "  long-term-semantic-authority=FORBIDDEN"
    echo "  creation-method.requires-independent-S-semantics=REJECT_IF_YES"
    echo "  producer-must-exit-after=Stage1->Stage2->Stage3 convergence"
    echo "  semantic-authority-after-creation=canonical-source"
    echo
    echo "candidate-methods:"
    echo "  A-one-time-reference-compiler:"
    echo "    requires-independent-S-semantics=YES"
    echo "    bounded=NO"
    echo "    reviewable=LOW"
    echo "    one-time=CLAIM_ONLY"
    echo "    verdict=REJECT_THIRD_COMPILER_RISK"
    echo
    echo "  B-mechanically-translated-implementation:"
    echo "    requires-independent-S-semantics=UNKNOWN"
    echo "    bounded=ONLY_IF_TRANSFORM_IS_SYNTAX_FREE_AND_SEMANTICS_FREE"
    echo "    reviewable=MEDIUM"
    echo "    one-time=YES"
    echo "    verdict=REJECT_UNLESS_PROVEN_MECHANICAL_NO_PARSER_SEMANTIC_GENERIC_OWNERSHIP"
    echo
    echo "  C-manually-reviewed-lowered-artifact:"
    echo "    requires-independent-S-semantics=NO_IF_INPUT_IS_ALREADY_LOWERED"
    echo "    bounded=YES"
    echo "    reviewable=MEDIUM_TO_HIGH"
    echo "    one-time=YES"
    echo "    verdict=POSSIBLE_BUT_ARTIFACT_CREATION_REVIEW_COST_HIGH"
    echo
    echo "  D-isolated-trusted-build-environment:"
    echo "    requires-independent-S-semantics=NO_IF_PRODUCER_IS_EXTERNAL_TRUST_ROOT_AND_NOT_MAINTAINED_IN_REPO"
    echo "    bounded=YES"
    echo "    reviewable=MANIFEST_AND_REGENERATION_BASED"
    echo "    one-time=YES"
    echo "    verdict=ACCEPTABLE_CEREMONY_SHAPE"
    echo
    echo "  E-recovered-release-ci-cache-artifact:"
    echo "    requires-independent-S-semantics=NO"
    echo "    bounded=YES"
    echo "    reviewable=MANIFEST_AND_HASH_BASED"
    echo "    one-time=YES"
    echo "    verdict=BEST_IF_FOUND_BUT_P0_4_FOUND_NONE"
    echo
    echo "artifact-level-comparison:"
    echo "  SSEED_IR:"
    echo "    consumer=$seed_aot_consumer"
    echo "    creation-complexity=MEDIUM"
    echo "    semantic-duplication=REJECT_IF_PRODUCER_PARSES_S"
    echo "    reviewability=MEDIUM"
    echo "    determinism=HIGH_IF_TEXT_CANONICAL"
    echo "    portability=MEDIUM"
    echo "    producer-lifetime=ONE_TIME"
    echo "    stage1-verification=RUN_AOT_THEN_STAGE1_BUILD"
    echo
    echo "  GENERATED_C:"
    echo "    consumer=$host_cc_available"
    echo "    creation-complexity=MEDIUM"
    echo "    semantic-duplication=REJECT_IF_GENERATOR_REIMPLEMENTS_S_SEMANTICS"
    echo "    reviewability=HIGHER_THAN_BINARY"
    echo "    determinism=HIGH_IF_FORMATTED_AND_HASHED"
    echo "    portability=HIGHER_THAN_NATIVE"
    echo "    producer-lifetime=ONE_TIME"
    echo "    stage1-verification=HOST_CC_THEN_STAGE1_BUILD"
    echo
    echo "  OBJECT:"
    echo "    consumer=$object_linker_available"
    echo "    creation-complexity=LOW_FOR_REPO_EXECUTOR"
    echo "    semantic-duplication=NO_IN_REPO"
    echo "    reviewability=LOW"
    echo "    determinism=TARGET_DEPENDENT"
    echo "    portability=LOW"
    echo "    producer-lifetime=ONE_TIME"
    echo "    stage1-verification=LINK_THEN_STAGE1_BUILD"
    echo
    echo "  NATIVE_EXECUTABLE:"
    echo "    consumer=OS_LOADER"
    echo "    creation-complexity=LOWEST_FOR_REPO_EXECUTOR"
    echo "    semantic-duplication=NO_IN_REPO"
    echo "    reviewability=LOWEST_REQUIRES_STRONG_PROVENANCE"
    echo "    determinism=TARGET_DEPENDENT"
    echo "    portability=LOW"
    echo "    producer-lifetime=ONE_TIME"
    echo "    stage1-verification=RUN_STAGE1_BUILD_STAGE2"
    echo
    echo "selected-creation-method=$selected_creation_method"
    echo "selected-artifact-level=$selected_artifact_level"
    echo "selection-reason=$selection_reason"
    echo
    echo "selected-method-properties:"
    echo "  requires-independent-S-semantics=$requires_independent_s_semantics"
    echo "  bounded=$bounded"
    echo "  reviewable=$reviewable"
    echo "  one-time=$one_time"
    echo "  producer-lifetime=$producer_lifetime"
    echo "  long-term-semantic-authority=$long_term_semantic_authority"
    echo
    echo "required-ceremony-output:"
    echo "  artifact=stage1"
    echo "  artifact-manifest=stage1.manifest"
    echo "  canonical-closure-snapshot=canonical-closure.txt"
    echo "  canonical-closure-hash=$canonical_snapshot_hash"
    echo "  creation-report=creation-report.txt"
    echo
    echo "success-conditions:"
    echo "  C1-artifact-creation=frozen-closure -> Stage1"
    echo "  C2-provenance=hashes + producer + target + manifest"
    echo "  C3-authority=Stage1 executes canonical build path"
    echo "  C4-regeneration=Stage1 -> Stage2"
    echo "  C5-self-regeneration=Stage2 -> Stage3"
    echo "  C6-convergence=Stage2 equivalence Stage3"
    echo "  existing-stage2-stage3-patterns=$existing_stage2_stage3_patterns"
    echo
    echo "next-edge="
    echo "  frozen canonical closure"
    echo "  -> first provenanced canonical Stage1 artifact"
    echo
    echo "DO_NOT_FIX_ABIUTILS_144=YES"
    echo "DO_NOT_FIX_HISTORICAL_IS_ERR=YES"
    echo "DO_NOT_IMPLEMENT_THIRD_COMPILER=YES"
    echo "DO_NOT_GENERATE_ARTIFACT_IN_P0_5A=YES"
} | tee "$report"

[ "$gate" = GREEN ]
