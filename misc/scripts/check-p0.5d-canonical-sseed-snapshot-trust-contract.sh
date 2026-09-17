#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
report="${P05D_CANONICAL_SSEED_SNAPSHOT_TRUST_REPORT:-"$root/.bootstrap/modular/p0.5d-canonical-sseed-snapshot-trust-contract.txt"}"
snapshot="${CANONICAL_STAGE1_SSEED_SNAPSHOT:-"$root/src/cmd/compile/bootstrap/canonical-stage1.sseed"}"
manifest="${CANONICAL_STAGE1_SSEED_MANIFEST:-"$root/src/cmd/compile/bootstrap/canonical-stage1.sseed.manifest"}"
expected_closure_hash="${CANONICAL_CLOSURE_HASH:-61bf30372b40e06defa4f8e8aadb6ed240b88e67982c73a3994feea61fe43fa9}"

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

file_bool() {
    [ -f "$1" ] && echo YES || echo NO
}

sha_file() {
    if [ -f "$1" ]; then
        shasum -a 256 "$1" | awk '{ print $1 }'
    else
        echo NONE
    fi
}

closure_count=0
canonical_snapshot=NOT_FOUND
canonical_snapshot_hash=NONE
source_binding_status=MISSING
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if [ "$closure_count" -gt 0 ] && grep -qx 'src/cmd/compile/modular_build_main.s' "$closure"; then
        canonical_snapshot=FOUND
    fi
    tmp_hashes="${TMPDIR:-/tmp}/s-p05d-closure-hashes.$$"
    trap 'rm -f "$tmp_hashes"' EXIT HUP INT TERM
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if [ -f "$root/$rel" ]; then
            shasum -a 256 "$root/$rel" | awk -v rel="$rel" '{ print $1 "  " rel }'
        else
            printf 'MISSING  %s\n' "$rel"
        fi
    done <"$closure" >"$tmp_hashes"
    canonical_snapshot_hash=$(shasum -a 256 "$tmp_hashes" | awk '{ print $1 }')
fi

if [ "$canonical_snapshot_hash" = "$expected_closure_hash" ]; then
    source_binding_status=MATCH
elif [ "$canonical_snapshot_hash" != NONE ]; then
    source_binding_status=MISMATCH
fi

sseed_consumer_exists=$(status_bool has_text 'emit_aot_from_ir_file|--emit-aot|SSEED-TARGET-V1' src/cmd/compile/seed)
sseed_header_gate=$(status_bool has_text 'SSEED-TARGET-V1' src/cmd/compile/seed/code/backend_registry.c src/cmd/compile/seed/code/native_backend.c src/cmd/compile/seed/s_seed.c)
sseed_source_mode_present=$(status_bool has_text 'compile_to_buffer|semantic_analyze|parse_program' src/cmd/compile/seed)
stage2_stage3_patterns=$(status_bool has_text 'stage2.*stage3|Stage2.*Stage3|cmp .*stage2.*stage3|bootstrap-convergence' makefile src/cmd/dist misc/scripts)

snapshot_exists=$(file_bool "$snapshot")
manifest_exists=$(file_bool "$manifest")
snapshot_sha256=$(sha_file "$snapshot")
manifest_sha256=$(sha_file "$manifest")

snapshot_header=NOT_CHECKED
if [ -f "$snapshot" ]; then
    if head -n 1 "$snapshot" | rg -q '^SSEED-TARGET-V1'; then
        snapshot_header=SSEED-TARGET-V1
    else
        snapshot_header=INVALID
    fi
fi

manifest_has_artifact_type=NO
manifest_has_source_hash=NO
manifest_has_producer=NO
manifest_has_semantic_trust=NO
manifest_has_convergence=NO
if [ -f "$manifest" ]; then
    manifest_has_artifact_type=$(status_bool rg -q 'artifact\.type *= *SSEED-TARGET-V1|artifact.type=SSEED-TARGET-V1' "$manifest")
    manifest_has_source_hash=$(status_bool rg -q "canonical-closure-hash *= *$expected_closure_hash|canonical-closure-hash=$expected_closure_hash" "$manifest")
    manifest_has_producer=$(status_bool rg -q 'producer\.(identity|version|hash)|producer.identity|producer.version|producer.hash' "$manifest")
    manifest_has_semantic_trust=$(status_bool rg -q 'one_time_semantic_trust|one-time-semantic-trust|independent_long_term_semantic_authority|produced_by_C_seed_semantic_authority' "$manifest")
    manifest_has_convergence=$(status_bool rg -q 'Stage1.*Stage2|Stage2.*Stage3|stage2-stage3-equivalence|convergence' "$manifest")
fi

contract_status=YELLOW
contract_reason=CONTRACT_DEFINED_SNAPSHOT_NOT_ACCEPTED
if [ "$canonical_snapshot" != FOUND ]; then
    contract_status=RED
    contract_reason=CANONICAL_CLOSURE_SNAPSHOT_NOT_FOUND
elif [ "$sseed_consumer_exists" != YES ] || [ "$sseed_header_gate" != YES ]; then
    contract_status=RED
    contract_reason=SSEED_AOT_CONSUMER_NOT_PROVEN
elif [ "$source_binding_status" != MATCH ]; then
    contract_reason=CONTRACT_DEFINED_CURRENT_WORKTREE_HASH_DIFFERS_FROM_FROZEN_BINDING
elif [ "$snapshot_exists" = YES ] && \
     [ "$snapshot_header" = SSEED-TARGET-V1 ] && \
     [ "$manifest_exists" = YES ] && \
     [ "$manifest_has_artifact_type" = YES ] && \
     [ "$manifest_has_source_hash" = YES ] && \
     [ "$manifest_has_producer" = YES ] && \
     [ "$manifest_has_semantic_trust" = YES ] && \
     [ "$manifest_has_convergence" = YES ]; then
    contract_status=YELLOW
    contract_reason=SNAPSHOT_PRESENT_REQUIRES_STAGE1_STAGE2_STAGE3_ACCEPTANCE
fi

{
    echo "P0.5d FIRST_CANONICAL_SSEED_SNAPSHOT_TRUST_CONTRACT"
    echo "P0_5D_CANONICAL_SSEED_SNAPSHOT_TRUST_CONTRACT=$contract_status"
    echo
    echo "SNAPSHOT_FORMAT=SSEED-TARGET-V1"
    echo "SOURCE_BINDING=canonical-closure-hash=$expected_closure_hash"
    echo "PRODUCER_CLASS=ONE_TIME_SEMANTIC_PRODUCER"
    echo "ONE_TIME_SEMANTIC_TRUST=EXPLICIT_REQUIRED"
    echo "FORBIDDEN_PRODUCER_RESPONSIBILITIES=S-parser,S-semantic-analysis,generic-resolution,method-resolution,ownership-borrow-NLL,drop-semantics,long-term-compiler-authority"
    echo "PROVENANCE_REQUIRED=YES"
    echo "AOT_CONSUMER=bin/s_seed --emit-aot"
    echo "STAGE1_ACCEPTANCE=snapshot -> s_seed --emit-aot -> Stage1 executes canonical build path"
    echo "CONVERGENCE_ACCEPTANCE=Stage1->Stage2; Stage2->Stage3; Stage2 equivalence Stage3"
    echo "FIRST_UNRESOLVED_TRUST_EDGE=canonical S source -> one-time semantic producer -> checked canonical SSEED snapshot"
    echo
    echo "identity:"
    echo "  artifact.type=SSEED-TARGET-V1"
    echo "  bootstrap-role=canonical-stage1-bootstrap-input"
    echo "  target=FROZEN_TARGET_REQUIRED"
    echo "  expected-snapshot-path=$snapshot"
    echo "  expected-manifest-path=$manifest"
    echo
    echo "source-binding:"
    echo "  canonical-snapshot=$canonical_snapshot"
    echo "  canonical-snapshot-path=$closure"
    echo "  canonical-snapshot-count=$closure_count"
    echo "  canonical-closure-hash=$canonical_snapshot_hash"
    echo "  expected-canonical-closure-hash=$expected_closure_hash"
    echo "  source-binding-status=$source_binding_status"
    echo
    echo "provenance-required:"
    echo "  producer.identity=REQUIRED"
    echo "  producer.version=REQUIRED"
    echo "  producer.hash=REQUIRED"
    echo "  production-method=REQUIRED"
    echo "  artifact.sha256=REQUIRED"
    echo "  artifact.target=REQUIRED"
    echo "  artifact.format-version=REQUIRED"
    echo "  source.canonical-closure-hash=REQUIRED"
    echo "  creation-report=REQUIRED"
    echo
    echo "semantic-trust-contract:"
    echo "  requires_S_semantic_decisions_in_AOT=NO"
    echo "  produced_by_C_seed_semantic_authority=NO"
    echo "  independent_long_term_semantic_authority=NO"
    echo "  one_time_semantic_trust=EXPLICIT"
    echo "  semantic-authority-after-bootstrap=canonical S source"
    echo "  bootstrap-artifact-role=trust-root-only"
    echo
    echo "allowed-one-time-producer-responsibilities:"
    echo "  create-checked-semantic-lowered-snapshot=YES"
    echo "  bind-output-to-frozen-canonical-closure-hash=YES"
    echo "  record-full-provenance=YES"
    echo "  exit-after-Stage2-Stage3-convergence=YES"
    echo
    echo "forbidden-producer-responsibilities:"
    echo "  permanent-S-parser=FORBIDDEN"
    echo "  permanent-S-semantic-analysis=FORBIDDEN"
    echo "  permanent-generic-resolution=FORBIDDEN"
    echo "  permanent-method-resolution=FORBIDDEN"
    echo "  permanent-ownership-borrow-NLL=FORBIDDEN"
    echo "  permanent-drop-semantics=FORBIDDEN"
    echo "  maintained-second-compiler-authority=FORBIDDEN"
    echo
    echo "aot-consumer-evidence:"
    echo "  sseed-consumer-exists=$sseed_consumer_exists"
    echo "  sseed-header-gate=$sseed_header_gate"
    echo "  seed-source-mode-present=$sseed_source_mode_present"
    echo "  seed-source-mode-role=NOT_AUTHORITY_FOR_CANONICAL_SSEED_AOT_PATH"
    echo "  consumer-role=mechanical artifact executor/encoder"
    echo
    echo "snapshot-state:"
    echo "  snapshot-exists=$snapshot_exists"
    echo "  snapshot-header=$snapshot_header"
    echo "  snapshot-sha256=$snapshot_sha256"
    echo "  manifest-exists=$manifest_exists"
    echo "  manifest-sha256=$manifest_sha256"
    echo "  manifest-has-artifact-type=$manifest_has_artifact_type"
    echo "  manifest-has-source-hash=$manifest_has_source_hash"
    echo "  manifest-has-producer=$manifest_has_producer"
    echo "  manifest-has-semantic-trust=$manifest_has_semantic_trust"
    echo "  manifest-has-convergence=$manifest_has_convergence"
    echo
    echo "acceptance-tests:"
    echo "  A1-snapshot-header=SSEED-TARGET-V1"
    echo "  A2-manifest-fields=artifact/source/producer/semantic-trust/convergence"
    echo "  A3-source-binding-hash=$expected_closure_hash"
    echo "  A4-provenance=producer.identity+producer.version+producer.hash+production-method+artifact.sha256"
    echo "  A5-semantic-trust=no-C-seed-semantic-authority+no-long-term-independent-authority+explicit-one-time-trust"
    echo "  A6-aot=s_seed --emit-aot snapshot -> Stage1"
    echo "  A7-authority=Stage1 executes canonical build path"
    echo "  A8-regeneration=Stage1 -> Stage2"
    echo "  A9-self-regeneration=Stage2 -> Stage3"
    echo "  A10-convergence=Stage2 equivalent Stage3"
    echo "  existing-stage2-stage3-patterns=$stage2_stage3_patterns"
    echo
    echo "verdict=$contract_reason"
    echo "selected-bootstrap-cut=SSEED_TARGET_V1"
    echo "p0.5c-eligibility=FROZEN_ELIGIBLE"
    echo
    echo "DO_NOT_PRODUCE_SNAPSHOT_IN_P0_5D=YES"
    echo "DO_NOT_MODIFY_SEED=YES"
    echo "DO_NOT_MODIFY_PARSER=YES"
    echo "DO_NOT_IMPLEMENT_MIR_TO_SSEED=YES"
    echo "DO_NOT_CREATE_ANOTHER_COMPILER=YES"
} | tee "$report"

[ "$contract_status" = GREEN ]
