#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
modular_dir="$root/.bootstrap/modular"
entry_rel="src/cmd/compile/modular_build_main.s"
closure="${STAGE0_CLOSURE:-"$modular_dir/canonical-closure.txt"}"
report="$modular_dir/b6.7.3e2r-bootstrap-artifact-boundary-reevaluation.txt"

tmp="${TMPDIR:-/tmp}/b6.7.3e2r-boundary.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$modular_dir"

run_optional() {
    local label="$1"
    shift
    set +e
    "$@" >"$tmp/$label.report" 2>&1
    local status=$?
    set -e
    echo "$status" >"$tmp/$label.status"
}

field_from() {
    local file="$1"
    local key="$2"
    if [ -f "$file" ]; then
        awk -F= -v key="$key" '$1 == key { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$file"
    else
        echo "UNKNOWN"
    fi
}

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

run_optional e3a bash "$root/misc/scripts/check-b6.7.3e3a-bootstrap-ir-generator-feasibility-audit.sh"

closure_count=0
closure_contains_entry=NO
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if grep -qx "$entry_rel" "$closure"; then
        closure_contains_entry=YES
    fi
fi

e3a_classification=$(field_from "$tmp/e3a.report" classification)
e3a_existing_generator=$(field_from "$tmp/e3a.report" existing-non-circular-generator)
e3a_blocker=$(field_from "$tmp/e3a.report" first-structural-blocker)

seed_ir_consumer=$(status_bool has_text 'emit_aot_from_ir_file|emit_native_from_ir_file' src/cmd/compile/seed)
canonical_emit_c_entry=$(status_bool has_text '--emit-c|compiler_emit_c|emit_selfhost_c|compile_selfhost_c' src/cmd/compile/compiler.s src/cmd/compile/selfhost/compiler.s makefile)
canonical_parser=$(status_bool has_text 'func parse_source' src/cmd/compile/internal/syntax src/s)
canonical_semantic=$(status_bool has_text 'check_source_file' src/cmd/compile/internal)
canonical_backend_build=$(status_bool has_text '^func build\(' src/cmd/compile/internal/backend_elf64.s)
host_cc_dependency=NO
if command -v cc >/dev/null 2>&1; then
    host_cc_dependency=YES
fi

generated_c_artifact_present=NO
if [ -f "$root/.bootstrap/modular/s_modular-stage1.c" ] || has_text 'write_stage1_c|write_next_stage|generated C mechanism|--emit-artifact-stage2' src/cmd/compile/stage0 makefile misc/scripts; then
    generated_c_artifact_present=YES
fi

stage1_binary_present=NO
if [ -x "$root/.bootstrap/modular/s_modular-stage1" ]; then
    stage1_binary_present=YES
fi

trusted_binary_contains_canonical_runtime=NO
if [ "$stage1_binary_present" = YES ] && strings "$root/.bootstrap/modular/s_modular-stage1" 2>/dev/null | rg -q 'modular_build_main|backend_elf64|compile\.internal\.semantic'; then
    trusted_binary_contains_canonical_runtime=YES
fi

trusted_binary_has_provenance=NO
if [ -f "$root/.bootstrap/modular/bootstrap-report.txt" ] && rg -q 'producer=|closure=|hash|canonical' "$root/.bootstrap/modular/bootstrap-report.txt"; then
    trusted_binary_has_provenance=PARTIAL
fi

stage2_stage3_equivalence=NOT_PROVEN
if [ -f "$root/.bootstrap/selfhost/stage2.ir" ] && [ -f "$root/.bootstrap/selfhost/stage3.ir" ]; then
    if cmp -s "$root/.bootstrap/selfhost/stage2.ir" "$root/.bootstrap/selfhost/stage3.ir"; then
        stage2_stage3_equivalence=YES
    else
        stage2_stage3_equivalence=NO
    fi
fi

candidate_b_producer_exists=NO
candidate_b_input=canonical-snapshot
candidate_b_output=bootstrap.ir
candidate_b_requires_existing_stage1=NO
candidate_b_requires_c_seed_semantic_expansion=NO
candidate_b_requires_bootstrap_subset_expansion=NO
candidate_b_canonical_semantics_preserved=DESIGN_ONLY
candidate_b_host_tool_dependency=existing-seed-ir/aot-consumer
candidate_b_regenerable=NO_GENERATOR
candidate_b_bootstrap_cycle=NO
candidate_b_permanent_dual_authority=NO
candidate_b_verdict=NOT_VIABLE_CURRENTLY
if [ "$e3a_existing_generator" = YES ]; then
    candidate_b_producer_exists=YES
    candidate_b_regenerable=YES
    candidate_b_canonical_semantics_preserved=YES
    candidate_b_verdict=VIABLE
fi

candidate_c_producer_exists=PARTIAL_SINGLE_SOURCE_EMIT_C
candidate_c_input=canonical-source-or-snapshot
candidate_c_output=generated-c
candidate_c_requires_existing_stage1=UNKNOWN_FOR_37_FILE_STAGE1
candidate_c_requires_c_seed_semantic_expansion=NO_IF_CANONICAL_EMIT_C_RUNS
candidate_c_requires_bootstrap_subset_expansion=NO_IF_GENERATED_C_IS_FROM_CANONICAL
candidate_c_canonical_semantics_preserved=PARTIAL
candidate_c_host_tool_dependency=host-cc
candidate_c_regenerable=UNKNOWN
candidate_c_bootstrap_cycle=UNKNOWN
candidate_c_permanent_dual_authority=NO_IF_C_IS_TRANSPORT_ONLY
candidate_c_verdict=PARTIAL_REQUIRES_PRODUCER_AUDIT
if [ "$canonical_emit_c_entry" != YES ]; then
    candidate_c_producer_exists=NO
    candidate_c_canonical_semantics_preserved=NO
    candidate_c_verdict=NOT_VIABLE
fi
if [ "$generated_c_artifact_present" = YES ] && has_text 'artifact-only: canonical-source-compilation=NOT_PROVEN|write_next_stage|bootstrap_subset_build' src/cmd/compile/stage0 makefile; then
    candidate_c_verdict=PARTIAL_EXISTING_C_ARTIFACT_IS_STUB_NOT_CANONICAL_STAGE1
fi

candidate_d_producer_exists=PARTIAL
candidate_d_input=trusted-checked-in-or-local-binary
candidate_d_output=stage1-executable
candidate_d_requires_existing_stage1=NO
candidate_d_requires_c_seed_semantic_expansion=NO
candidate_d_requires_bootstrap_subset_expansion=NO
candidate_d_canonical_semantics_preserved=NOT_PROVEN
candidate_d_host_tool_dependency=platform-binary
candidate_d_regenerable=NOT_PROVEN
candidate_d_bootstrap_cycle=NO
candidate_d_permanent_dual_authority=NO_IF_FROZEN_AND_REGENERATED_BY_STAGE2_STAGE3
candidate_d_verdict=PARTIAL_TRUST_ROOT_CANDIDATE
if [ "$trusted_binary_contains_canonical_runtime" != YES ]; then
    candidate_d_verdict=NOT_VIABLE_CURRENT_ARTIFACT_LACKS_CANONICAL_RUNTIME
fi
if [ "$trusted_binary_contains_canonical_runtime" = YES ] && [ "$trusted_binary_has_provenance" != NO ] && [ "$stage2_stage3_equivalence" = YES ]; then
    candidate_d_canonical_semantics_preserved=YES
    candidate_d_regenerable=YES
    candidate_d_verdict=VIABLE_BOUNDED_TRUST_ROOT
fi

recommended_next=REOPEN_ARTIFACT_BOUNDARY
selected_candidate=NONE
classification=ARTIFACT_BOUNDARY_REOPEN_REQUIRED

if [ "$candidate_b_verdict" = VIABLE ]; then
    selected_candidate=B-bootstrap-ir
    recommended_next=IMPLEMENT_E3_BOOTSTRAP_IR_PRODUCER
    classification=ARTIFACT_BOUNDARY_SELECTED
elif [ "$candidate_c_verdict" = PARTIAL_REQUIRES_PRODUCER_AUDIT ] || [ "$candidate_c_verdict" = PARTIAL_EXISTING_C_ARTIFACT_IS_STUB_NOT_CANONICAL_STAGE1 ]; then
    selected_candidate=C-generated-c
    recommended_next=CANDIDATE_C_GENERATED_C_PRODUCER_AUDIT
    classification=ARTIFACT_BOUNDARY_REOPEN_REQUIRED
elif [ "$candidate_d_verdict" = PARTIAL_TRUST_ROOT_CANDIDATE ] || [ "$candidate_d_verdict" = NOT_VIABLE_CURRENT_ARTIFACT_LACKS_CANONICAL_RUNTIME ]; then
    selected_candidate=D-trusted-bootstrap-artifact
    recommended_next=TRUSTED_BOOTSTRAP_ARTIFACT_PROVENANCE_AUDIT
    classification=ARTIFACT_BOUNDARY_REOPEN_REQUIRED
fi

{
    echo "B6.7.3e2r Canonical Stage1 Bootstrap Artifact Boundary Re-evaluation"
    echo "purpose=read-only-reopen-boundary-audit-no-producer-implementation"
    echo "canonical-entry=$entry_rel"
    echo "canonical-closure=$closure"
    echo "canonical-closure-count=$closure_count"
    echo "canonical-closure-contains-entry=$closure_contains_entry"
    echo "invariant-bootstrap-cycle=FORBIDDEN"
    echo "invariant-permanent-dual-semantic-authority=FORBIDDEN"
    echo "invariant-stage0-capability-growth=BOOTSTRAP_BOUNDED_ONLY"
    echo "new-evidence-source=B6.7.3e3a"
    echo "e3a-classification=$e3a_classification"
    echo "e3a-existing-non-circular-generator=$e3a_existing_generator"
    echo "e3a-first-structural-blocker=$e3a_blocker"
    echo "canonical-parser=$canonical_parser"
    echo "canonical-semantic=$canonical_semantic"
    echo "canonical-backend-build=$canonical_backend_build"
    echo "canonical-emit-c-entry=$canonical_emit_c_entry"
    echo "seed-ir-consumer=$seed_ir_consumer"
    echo "host-cc-dependency=$host_cc_dependency"
    echo "candidate=B-bootstrap-ir"
    echo "candidate-B-producer-exists=$candidate_b_producer_exists"
    echo "candidate-B-producer-input=$candidate_b_input"
    echo "candidate-B-producer-output=$candidate_b_output"
    echo "candidate-B-requires-existing-stage1=$candidate_b_requires_existing_stage1"
    echo "candidate-B-requires-c-seed-semantic-expansion=$candidate_b_requires_c_seed_semantic_expansion"
    echo "candidate-B-requires-bootstrap-subset-expansion=$candidate_b_requires_bootstrap_subset_expansion"
    echo "candidate-B-canonical-semantics-preserved=$candidate_b_canonical_semantics_preserved"
    echo "candidate-B-host-tool-dependency=$candidate_b_host_tool_dependency"
    echo "candidate-B-regenerable=$candidate_b_regenerable"
    echo "candidate-B-bootstrap-cycle=$candidate_b_bootstrap_cycle"
    echo "candidate-B-permanent-dual-authority=$candidate_b_permanent_dual_authority"
    echo "candidate-B-verdict=$candidate_b_verdict"
    echo "candidate=C-generated-c"
    echo "candidate-C-producer-exists=$candidate_c_producer_exists"
    echo "candidate-C-producer-input=$candidate_c_input"
    echo "candidate-C-producer-output=$candidate_c_output"
    echo "candidate-C-requires-existing-stage1=$candidate_c_requires_existing_stage1"
    echo "candidate-C-requires-c-seed-semantic-expansion=$candidate_c_requires_c_seed_semantic_expansion"
    echo "candidate-C-requires-bootstrap-subset-expansion=$candidate_c_requires_bootstrap_subset_expansion"
    echo "candidate-C-canonical-semantics-preserved=$candidate_c_canonical_semantics_preserved"
    echo "candidate-C-host-tool-dependency=$candidate_c_host_tool_dependency"
    echo "candidate-C-regenerable=$candidate_c_regenerable"
    echo "candidate-C-bootstrap-cycle=$candidate_c_bootstrap_cycle"
    echo "candidate-C-permanent-dual-authority=$candidate_c_permanent_dual_authority"
    echo "candidate-C-existing-generated-c-artifact=$generated_c_artifact_present"
    echo "candidate-C-verdict=$candidate_c_verdict"
    echo "candidate=D-trusted-bootstrap-artifact"
    echo "candidate-D-producer-exists=$candidate_d_producer_exists"
    echo "candidate-D-producer-input=$candidate_d_input"
    echo "candidate-D-producer-output=$candidate_d_output"
    echo "candidate-D-requires-existing-stage1=$candidate_d_requires_existing_stage1"
    echo "candidate-D-requires-c-seed-semantic-expansion=$candidate_d_requires_c_seed_semantic_expansion"
    echo "candidate-D-requires-bootstrap-subset-expansion=$candidate_d_requires_bootstrap_subset_expansion"
    echo "candidate-D-canonical-semantics-preserved=$candidate_d_canonical_semantics_preserved"
    echo "candidate-D-host-tool-dependency=$candidate_d_host_tool_dependency"
    echo "candidate-D-regenerable=$candidate_d_regenerable"
    echo "candidate-D-bootstrap-cycle=$candidate_d_bootstrap_cycle"
    echo "candidate-D-permanent-dual-authority=$candidate_d_permanent_dual_authority"
    echo "candidate-D-current-stage1-present=$stage1_binary_present"
    echo "candidate-D-current-stage1-canonical-runtime=$trusted_binary_contains_canonical_runtime"
    echo "candidate-D-provenance=$trusted_binary_has_provenance"
    echo "candidate-D-stage2-stage3-equivalence=$stage2_stage3_equivalence"
    echo "candidate-D-verdict=$candidate_d_verdict"
    echo "selected-candidate=$selected_candidate"
    echo "recommended-next=$recommended_next"
    echo "classification=$classification"
} | tee "$report"

if [ "$classification" != ARTIFACT_BOUNDARY_SELECTED ]; then
    exit 1
fi
