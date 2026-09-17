#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
report="${P05C_BOOTSTRAP_SEMANTIC_CUT_REPORT:-"$root/.bootstrap/modular/p0.5c-bootstrap-semantic-cut-audit.txt"}"

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

exec_bool() {
    [ -x "$1" ] && echo YES || echo NO
}

closure_count=0
canonical_snapshot=NOT_FOUND
canonical_snapshot_hash=NONE
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if [ "$closure_count" -gt 0 ] && grep -qx 'src/cmd/compile/modular_build_main.s' "$closure"; then
        canonical_snapshot=FOUND
    fi
    tmp_hashes="${TMPDIR:-/tmp}/s-p05c-closure-hashes.$$"
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

canonical_mir_artifact="$root/src/cmd/compile/bootstrap/stage1.mir"
canonical_lowered_artifact="$root/src/cmd/compile/bootstrap/stage1.lowered"
canonical_sseed_artifact="$root/src/cmd/compile/bootstrap/bootstrap.ir"
canonical_object_artifact="$root/src/cmd/compile/bootstrap/stage1.o"
canonical_native_artifact="$root/src/cmd/compile/bootstrap/stage1"

mir_producer_path=$(status_bool has_text 'lower_main_to_mir|mir_graph|build_ownership_facts_from_mir' src/cmd/compile/internal)
mir_has_language_decisions=$(status_bool has_text 'ownership|borrow|drop|generic|method|monomorph|type_name|check_source_file' src/cmd/compile/internal/mir.s src/cmd/compile/internal/ir/lower.s src/cmd/compile/internal/mono/monomorphization.s src/cmd/compile/internal/backend_elf64.s)
lowered_view_exists=$(status_bool has_text 'canonical-lowered-view version=1|lowered_view_from_mir' src/cmd/compile/internal/ir/lower.s src/cmd/compile/compiler.s misc/scripts)
sseed_consumer_exists=$(status_bool has_text 'emit_aot_from_ir_file|--emit-aot|SSEED-TARGET-V1' src/cmd/compile/seed makefile)
sseed_consumer_reparses_s=NO
if has_text 'if .*\\.s|compile_to_buffer|semantic_analyze|parse_program' src/cmd/compile/seed/s_seed.c src/cmd/compile/seed/code/backend_registry.c; then
    sseed_consumer_reparses_s=ENTRYPOINT_HAS_SOURCE_MODE_BUT_AOT_PATH_IS_IR_HEADER_GATED
fi

host_linker=NO
if command -v ld >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; then
    host_linker=YES
fi

host_loader=YES

selected_semantic_cut=NONE
selected_reason=NO_CHECKED_LOWERED_BOOTSTRAP_SNAPSHOT
gate=RED

if [ "$(file_bool "$canonical_sseed_artifact")" = YES ] && [ "$sseed_consumer_exists" = YES ]; then
    selected_semantic_cut=SSEED_TARGET_V1
    selected_reason=LOWEST_TEXTUAL_CHECKED_REPRESENTATION_WITH_EXISTING_MECHANICAL_AOT_CONSUMER
    gate=YELLOW
elif [ "$(file_bool "$canonical_lowered_artifact")" = YES ]; then
    selected_semantic_cut=LOWERED_EXECUTABLE_IR
    selected_reason=LOWERED_ARTIFACT_EXISTS_BUT_MECHANICAL_CONSUMER_MUST_BE_DEFINED
    gate=YELLOW
elif [ "$(file_bool "$canonical_mir_artifact")" = YES ]; then
    selected_semantic_cut=CANONICAL_MIR
    selected_reason=MIR_ARTIFACT_EXISTS_BUT_BACKEND_SEMANTIC_RESIDUE_MUST_BE_AUDITED
    gate=YELLOW
elif [ "$(file_bool "$canonical_object_artifact")" = YES ]; then
    selected_semantic_cut=OBJECT
    selected_reason=OBJECT_ARTIFACT_EXISTS_WITH_HOST_LINKER
    gate=YELLOW
elif [ "$(exec_bool "$canonical_native_artifact")" = YES ]; then
    selected_semantic_cut=NATIVE_EXECUTABLE
    selected_reason=NATIVE_ARTIFACT_EXISTS_WITH_OS_LOADER
    gate=YELLOW
fi

{
    echo "P0.5c BOOTSTRAP_ARTIFACT_INPUT_SEMANTIC_CUT_AUDIT"
    echo "P0_5C_BOOTSTRAP_SEMANTIC_CUT=$gate"
    echo
    echo "corrected-bootstrap-model:"
    echo "  frozen canonical closure"
    echo "  -> ONE_TIME_SEMANTIC_TRUST"
    echo "  -> checked semantically-lowered bootstrap snapshot"
    echo "  -> BOUNDED_MECHANICAL_PRODUCER"
    echo "  -> native Stage1"
    echo "  -> Stage2 -> Stage3 -> convergence"
    echo
    echo "source:"
    echo "  closure=$closure"
    echo "  count=$closure_count"
    echo "  hash=$canonical_snapshot_hash"
    echo "  status=$canonical_snapshot"
    echo
    echo "semantic-cut-candidates:"
    echo "  S_SOURCE:"
    echo "    artifact-exists=$canonical_snapshot"
    echo "    requires-S-semantics-after-cut=YES"
    echo "    mechanical-consumer-exists=NO"
    echo "    reviewability=HIGH_SOURCE_READABLE"
    echo "    trust-surface=FULL_COMPILER_REQUIRED"
    echo "    verdict=REJECT_PRODUCER_WOULD_NEED_PARSER_SEMANTIC_GENERIC_METHOD_OWNERSHIP"
    echo
    echo "  CANONICAL_MIR:"
    echo "    artifact-exists=$(file_bool "$canonical_mir_artifact")"
    echo "    producer-path-exists=$mir_producer_path"
    echo "    requires-S-semantics-after-cut=UNKNOWN_TO_PARTIAL"
    echo "    language-decisions-may-remain=$mir_has_language_decisions"
    echo "    mechanical-consumer-exists=NO_FULL_STAGE1_CONSUMER"
    echo "    reviewability=MEDIUM"
    echo "    portability=MEDIUM"
    echo "    verdict=INTERESTING_BUT_CUT_MAY_BE_TOO_HIGH_AND_ARTIFACT_MISSING"
    echo
    echo "  LOWERED_EXECUTABLE_IR:"
    echo "    artifact-exists=$(file_bool "$canonical_lowered_artifact")"
    echo "    lowered-view-exists=$lowered_view_exists"
    echo "    requires-S-semantics-after-cut=LOW_IF_FULLY_LOWERED"
    echo "    mechanical-consumer-exists=NO_FULL_STAGE1_CONSUMER"
    echo "    reviewability=MEDIUM_TO_HIGH"
    echo "    portability=MEDIUM"
    echo "    verdict=PREFERRED_SHAPE_IF_FULL_LOWERED_SNAPSHOT_AND_ENCODER_ARE_DEFINED"
    echo
    echo "  SSEED_TARGET_V1:"
    echo "    artifact-exists=$(file_bool "$canonical_sseed_artifact")"
    echo "    requires-S-semantics-after-cut=NO_IF_ARTIFACT_IS_ALREADY_CANONICAL_STAGE1"
    echo "    mechanical-consumer-exists=$sseed_consumer_exists"
    echo "    consumer=bin/s_seed --emit-aot"
    echo "    consumer-role=bootstrap artifact executor/encoder, not S compiler"
    echo "    consumer-source-mode-note=$sseed_consumer_reparses_s"
    echo "    reviewability=MEDIUM_TEXTUAL_IR"
    echo "    determinism=HIGH_IF_FORMAT_CANONICAL"
    echo "    portability=MEDIUM_TARGET_BACKEND_DEPENDENT"
    echo "    verdict=BEST_PRACTICAL_CUT_IF_CHECKED_CANONICAL_SSEED_SNAPSHOT_EXISTS"
    echo
    echo "  OBJECT:"
    echo "    artifact-exists=$(file_bool "$canonical_object_artifact")"
    echo "    requires-S-semantics-after-cut=NO"
    echo "    mechanical-consumer-exists=$host_linker"
    echo "    consumer=host linker"
    echo "    reviewability=LOW"
    echo "    portability=LOW"
    echo "    verdict=VALID_LOW_CUT_IF_PROVENANCED_OBJECT_EXISTS"
    echo
    echo "  NATIVE:"
    echo "    artifact-exists=$(file_bool "$canonical_native_artifact")"
    echo "    executable=$(exec_bool "$canonical_native_artifact")"
    echo "    requires-S-semantics-after-cut=NO"
    echo "    mechanical-consumer-exists=$host_loader"
    echo "    consumer=OS loader"
    echo "    reviewability=LOWEST"
    echo "    portability=LOW"
    echo "    verdict=VALID_LOWEST_CUT_IF_PROVENANCED_NATIVE_EXISTS"
    echo
    echo "selected-semantic-cut=$selected_semantic_cut"
    echo "selected-reason=$selected_reason"
    echo
    echo "trust-placement:"
    echo "  first-bootstrap-artifact-cannot-be-derived-from-nothing=YES"
    echo "  minimize-one-time-semantic-trust=YES"
    echo "  one-time-semantic-trust-target=checked semantically-lowered bootstrap snapshot"
    echo "  long-term-semantic-authority=canonical S source"
    echo
    echo "next-edge="
    echo "  define or recover checked semantically-lowered bootstrap snapshot"
    echo "  -> bounded mechanical producer"
    echo
    echo "DO_NOT_TREAT_SOURCE_AS_MECHANICAL_INPUT=YES"
    echo "DO_NOT_IMPLEMENT_THIRD_COMPILER=YES"
    echo "DO_NOT_FIX_ABIUTILS_144=YES"
    echo "DO_NOT_GENERATE_STAGE1_IN_P0_5C=YES"
} | tee "$report"

[ "$gate" = GREEN ]
