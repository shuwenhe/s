#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
entry_rel="src/cmd/compile/modular_build_main.s"
entry="$root/$entry_rel"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
historical_root="${P01_HISTORICAL_ROOT:-"$root/.bootstrap/selfhost/stage1"}"
report="${P01_CANONICAL_ARTIFACT_PRODUCER_FEASIBILITY_REPORT:-"$root/.bootstrap/modular/p0.1-canonical-artifact-producer-feasibility.txt"}"

tmp="${TMPDIR:-/tmp}/s-p0.1-feasibility.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
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

closure_count=0
canonical_snapshot=NOT_FOUND
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if [ "$closure_count" -gt 0 ] && grep -qx "$entry_rel" "$closure"; then
        canonical_snapshot=FOUND
    fi
fi

canonical_parse_entry=$(status_bool has_text 'func parse_source' src/cmd/compile/internal/syntax src/s)
canonical_semantic_entry=$(status_bool has_text 'check_source_file' src/cmd/compile/internal/semantic.s src/cmd/compile/internal/backend_elf64.s)
canonical_mono_entry=$(status_bool has_text 'monomorphize_file' src/cmd/compile/internal/mono/monomorphization.s src/cmd/compile/internal/backend_elf64.s)
canonical_mir_entry=$(status_bool has_text 'func lower_.*to_mir|lower_main_to_mir|mir_graph' src/cmd/compile/internal/ir/lower.s src/cmd/compile/internal/mir.s)
canonical_pipeline_edge=$(status_bool has_text 'parse_source.*check_source_file|check_source_file|monomorphize_file|lower_main_to_mir' src/cmd/compile/internal/backend_elf64.s)

mir_structured_authority=$(status_bool has_text 'CANONICAL / SEMANTIC|mir_graph|mir_basic_block|mir_statement|mir_terminator' src/cmd/compile/internal/mir.s)
mir_deterministic_ids=$(status_bool has_text 'Deterministic dense ids|build_mir_point_map' src/cmd/compile/internal/mir.s)
mir_lowered_view_exists=$(status_bool has_text 'func lowered_view_from_mir|canonical-lowered-view version=1|view-role=READ_ONLY' src/cmd/compile/internal/ir/lower.s)
mir_to_sseed_adapter_exists=$(status_bool has_text 'emit_.*sseed|sseed_.*emit|mir_.*sseed|sseed_.*mir|bootstrap_ir_from_mir|SSEED-TARGET-V1' src/cmd/compile/internal/mir.s src/cmd/compile/internal/ir src/cmd/compile/internal/backend_elf64.s)
seed_sseed_consumer=$(status_bool has_text 'emit_aot_from_ir_file|emit_native_from_ir_file|--emit-aot' src/cmd/compile/seed)

q1_adapter_thin_candidate=NO
q1_representation_gap=LARGE
q1_first_missing_edge='canonical MIR -> full SSEED-TARGET-V1 artifact adapter'
if [ "$canonical_mir_entry" = YES ] && [ "$mir_structured_authority" = YES ] && [ "$mir_deterministic_ids" = YES ] && [ "$seed_sseed_consumer" = YES ]; then
    q1_adapter_thin_candidate=POSSIBLE
fi
if [ "$mir_to_sseed_adapter_exists" = YES ]; then
    q1_adapter_thin_candidate=YES
    q1_representation_gap=UNKNOWN_EXISTING_ADAPTER_REQUIRES_REVIEW
    q1_first_missing_edge=NONE
elif [ "$mir_lowered_view_exists" = YES ]; then
    q1_representation_gap=MEDIUM_TO_LARGE_READ_ONLY_VIEW_EXISTS_FULL_ARTIFACT_EMITTER_MISSING
fi

historical_root_exists=NO
historical_root_executable=NO
historical_root_file=UNKNOWN
if [ -f "$historical_root" ]; then
    historical_root_exists=YES
    historical_root_file=$(file "$historical_root" 2>/dev/null || echo UNKNOWN)
fi
if [ -x "$historical_root" ]; then
    historical_root_executable=YES
fi

historical_root_runs=NOT_RUN
historical_root_current_pipeline=NOT_PROVEN
historical_root_first_error=NONE
if [ "$historical_root_executable" = YES ] && [ -f "$entry" ]; then
    set +e
    "$historical_root" "$entry" "$tmp/current-canonical.ir" >"$tmp/historical.stdout" 2>"$tmp/historical.stderr"
    historical_status=$?
    set -e
    historical_root_runs=$historical_status
    if [ "$historical_status" -eq 0 ] && [ -s "$tmp/current-canonical.ir" ]; then
        historical_root_current_pipeline=PROVEN
    else
        historical_root_first_error=$(sed -n '1p' "$tmp/historical.stderr" "$tmp/historical.stdout" 2>/dev/null | head -n 1)
        if [ -z "$historical_root_first_error" ]; then
            historical_root_first_error=UNKNOWN
        fi
    fi
fi

q2_historical_executor=NO
q2_first_missing_edge='trusted executor that can run current canonical Parser/Semantic/Mono/MIR once'
if [ "$historical_root_current_pipeline" = PROVEN ]; then
    q2_historical_executor=YES
    q2_first_missing_edge=NONE
fi

q3_non_circular_chain=NO
q3_reason=missing-current-canonical-executor
if [ "$q1_adapter_thin_candidate" = YES ] && [ "$q2_historical_executor" = YES ]; then
    q3_non_circular_chain=YES
    q3_reason=historical-root-runs-current-canonical-semantics-and-existing-adapter-emits-artifact
elif [ "$q1_adapter_thin_candidate" = POSSIBLE ] && [ "$q2_historical_executor" = YES ]; then
    q3_reason=adapter-missing-but-executor-exists
elif [ "$q1_adapter_thin_candidate" = NO ] && [ "$q2_historical_executor" = YES ]; then
    q3_reason=canonical-mir-to-artifact-adapter-not-established
fi

gate=RED
if [ "$q3_non_circular_chain" = YES ]; then
    gate=GREEN
fi

{
    echo "P0.1 CANONICAL_ARTIFACT_PRODUCER_FEASIBILITY"
    echo "P0_1_CANONICAL_ARTIFACT_PRODUCER_FEASIBILITY=$gate"
    echo
    echo "canonical-snapshot=$canonical_snapshot"
    echo "canonical-snapshot-path=$closure"
    echo "canonical-snapshot-count=$closure_count"
    echo
    echo "canonical-pipeline-static:"
    echo "  parse-source=$canonical_parse_entry"
    echo "  semantic-check=$canonical_semantic_entry"
    echo "  monomorphization=$canonical_mono_entry"
    echo "  mir-lowering=$canonical_mir_entry"
    echo "  backend-path-links-pipeline=$canonical_pipeline_edge"
    echo
    echo "Q1 canonical MIR -> SSEED IR thin adapter:"
    echo "  mir-structured-authority=$mir_structured_authority"
    echo "  mir-deterministic-ids=$mir_deterministic_ids"
    echo "  lowered-view-from-mir=$mir_lowered_view_exists"
    echo "  full-mir-to-sseed-adapter-exists=$mir_to_sseed_adapter_exists"
    echo "  sseed-ir-consumer=$seed_sseed_consumer"
    echo "  thin-adapter-feasibility=$q1_adapter_thin_candidate"
    echo "  representation-gap=$q1_representation_gap"
    echo "  first-missing-edge=$q1_first_missing_edge"
    echo
    echo "Q2 historical root can execute current canonical pipeline once:"
    echo "  historical-root=$historical_root"
    echo "  historical-root-exists=$historical_root_exists"
    echo "  historical-root-executable=$historical_root_executable"
    echo "  historical-root-file=$historical_root_file"
    echo "  probe-command=<historical-root> $entry_rel <tmp-ir>"
    echo "  probe-exit=$historical_root_runs"
    echo "  current-canonical-pipeline=$historical_root_current_pipeline"
    echo "  first-error=$historical_root_first_error"
    echo "  executor-feasibility=$q2_historical_executor"
    echo "  first-missing-edge=$q2_first_missing_edge"
    echo
    echo "Q3 non-circular historical-root -> current canonical semantics -> bootstrap artifact -> Stage1:"
    echo "  non-circular-chain=$q3_non_circular_chain"
    echo "  reason=$q3_reason"
    echo
    echo "DIRECT_SEED_CLOSURE=REJECTED"
    echo "SEED_REASSIGNMENT_FIX=FORBIDDEN_BY_CURRENT_GATE"
    echo "ADAPTER_IMPLEMENTATION=NOT_STARTED"
} | tee "$report"

[ "$gate" = GREEN ]
