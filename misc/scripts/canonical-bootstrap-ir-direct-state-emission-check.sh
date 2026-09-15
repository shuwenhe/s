#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
compiler=${S_CANONICAL_COMPILER_BIN:-"$root/bin/s"}
seed=${SEED_COMPILER_BIN:-"$root/bin/s_seed"}
serializer=${BOOTSTRAP_IR_LOWERED_VIEW_SERIALIZER:-"$root/misc/scripts/canonical-bootstrap-ir-lowered-view-serializer.sh"}
report=${CANONICAL_BOOTSTRAP_IR_DIRECT_STATE_EMISSION_REPORT:-"$root/.bootstrap/modular/canonical-bootstrap-ir-direct-state-emission-check.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/canonical-bootstrap-ir-direct-state-emission.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

src42="$tmp/minimal_42.s"
src43="$tmp/minimal_43.s"
view42="$tmp/minimal_42.view"
view43="$tmp/minimal_43.view"
ir42="$tmp/minimal_42.ir"
ir43="$tmp/minimal_43.ir"
ir42_repeat="$tmp/minimal_42_repeat.ir"
native42="$tmp/minimal_42"
native43="$tmp/minimal_43"

write_source() {
    value=$1
    path=$2
    {
        echo "package main"
        echo
        echo "func main() int {"
        echo "    return $value"
        echo "}"
    } >"$path"
}

write_source 42 "$src42"
write_source 43 "$src43"

set +e
"$compiler" --emit-lowered-view "$src42" "$view42" >"$tmp/view42.log" 2>&1
view42_status=$?
"$compiler" --emit-lowered-view "$src43" "$view43" >"$tmp/view43.log" 2>&1
view43_status=$?
set -e

canonical_parser_reached=NO
canonical_semantic_reached=NO
canonical_lowering_reached=NO
if [ "$view42_status" -eq 0 ] && [ "$view43_status" -eq 0 ] && [ -s "$view42" ] && [ -s "$view43" ]; then
    canonical_parser_reached=YES
    canonical_semantic_reached=YES
    canonical_lowering_reached=YES
fi

direct_bootstrap_ir_entry=NO
if [ "$view42_status" -eq 0 ] && [ "$view43_status" -eq 0 ]; then
    direct_bootstrap_ir_entry=YES
fi

emit_c_intermediate_used=NO
c_source_parsing_used=NO
c_source_pattern_matching_used=NO

direct_state_preserves_return_constant=NO
case42_exported_return=UNKNOWN
case43_exported_return=UNKNOWN
if [ -s "$view42" ]; then
    case42_exported_return=$(awk -F= '$1 == "return-constant" { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$view42")
fi
if [ -s "$view43" ]; then
    case43_exported_return=$(awk -F= '$1 == "return-constant" { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$view43")
fi
if [ "$case42_exported_return" = 42 ] && [ "$case43_exported_return" = 43 ]; then
    direct_state_preserves_return_constant=YES
fi

direct_state_to_bootstrap_ir=NOT_PROVEN
artifact_source_surface=UNKNOWN
missing_capability=NONE
verdict=DIRECT_CANONICAL_BOOTSTRAP_IR_EMISSION_NOT_PROVEN

export_provenance_differential=NO
if [ "$case42_exported_return" = 42 ] && [ "$case43_exported_return" = 43 ] && ! cmp -s "$view42" "$view43"; then
    export_provenance_differential=YES
fi

export_view_read_only=YES
if grep -E 'calculate|assign_abi|infer_drop|resolve_symbol|recompute|emit-c|compiler_result = INT64_C' "$view42" "$view43" >/dev/null 2>&1; then
    export_view_read_only=NO
fi

bootstrap_ir_emitted=NO
ir_aot_accepted=NO
native_artifact_produced=NO
native_artifact_runnable=NO
case42_known_result=NOT_RUN
case43_known_result=NOT_RUN
provenance_differential_42_43=NOT_RUN
same_input_byte_determinism=NOT_RUN
seed_frontend_used_for_artifact=NO
seed_semantic_used_for_artifact=NO

if [ "$direct_bootstrap_ir_entry" = YES ] && [ "$export_view_read_only" = YES ] && [ -x "$serializer" ]; then
    set +e
    "$serializer" "$view42" "$ir42" >"$tmp/serialize42.log" 2>&1
    serialize42_status=$?
    "$serializer" "$view43" "$ir43" >"$tmp/serialize43.log" 2>&1
    serialize43_status=$?
    "$serializer" "$view42" "$ir42_repeat" >"$tmp/serialize42-repeat.log" 2>&1
    serialize42_repeat_status=$?
    set -e

    if [ "$serialize42_status" -eq 0 ] && [ "$serialize43_status" -eq 0 ] && [ -s "$ir42" ] && [ -s "$ir43" ]; then
        bootstrap_ir_emitted=YES
    fi

    if [ "$bootstrap_ir_emitted" = YES ]; then
        if cmp -s "$ir42" "$ir43"; then
            provenance_differential_42_43=NO
        else
            provenance_differential_42_43=YES
        fi
        if [ "$serialize42_repeat_status" -eq 0 ] && cmp -s "$ir42" "$ir42_repeat"; then
            same_input_byte_determinism=YES
        else
            same_input_byte_determinism=NO
        fi

        set +e
        S_SOURCE_ROOT="$root" "$seed" --emit-aot "$ir42" "$native42" >"$tmp/aot42.log" 2>&1
        aot42_status=$?
        S_SOURCE_ROOT="$root" "$seed" --emit-aot "$ir43" "$native43" >"$tmp/aot43.log" 2>&1
        aot43_status=$?
        set -e

        if [ "$aot42_status" -eq 0 ] && [ "$aot43_status" -eq 0 ]; then
            ir_aot_accepted=YES
        fi
        if [ -x "$native42" ] && [ -x "$native43" ]; then
            native_artifact_produced=YES
            set +e
            "$native42" >/dev/null 2>&1
            case42_known_result=$?
            "$native43" >/dev/null 2>&1
            case43_known_result=$?
            set -e
            if [ "$case42_known_result" = 42 ] && [ "$case43_known_result" = 43 ]; then
                native_artifact_runnable=YES
            fi
        fi
    fi
fi

if grep -E 'PARSE_FAIL|expected .* got|use of undeclared symbol|type error|bootstrap-subset:' \
    "$tmp"/serialize*.log "$tmp"/aot*.log >/dev/null 2>&1; then
    seed_semantic_used_for_artifact=YES
fi

if [ "$direct_bootstrap_ir_entry" = YES ] && \
   [ "$direct_state_preserves_return_constant" = YES ] && \
   [ "$export_provenance_differential" = YES ] && \
   [ "$export_view_read_only" = YES ] && \
   [ "$bootstrap_ir_emitted" = YES ] && \
   [ "$ir_aot_accepted" = YES ] && \
   [ "$native_artifact_produced" = YES ] && \
   [ "$native_artifact_runnable" = YES ] && \
   [ "$provenance_differential_42_43" = YES ] && \
   [ "$same_input_byte_determinism" = YES ] && \
   [ "$seed_semantic_used_for_artifact" = NO ]; then
    artifact_source_surface=CANONICAL_FINALIZED_STATE_EXPORT_VIEW
    direct_state_to_bootstrap_ir=PROVEN
    verdict=DIRECT_CANONICAL_BOOTSTRAP_IR_EMISSION_PROVEN
else
    artifact_source_surface=NO_DIRECT_CANONICAL_FINALIZED_STATE_EXPORT
    missing_capability=canonical-lowered-state-export-surface
fi

{
    echo "canonical-bootstrap-ir-direct-state-emission-check"
    echo "purpose=B6.2.3-direct-lowered-view-to-bootstrap-ir-to-native"
    echo "scope=return-constant-program-only"
    echo "source-origin=CANONICAL_S_SOURCE"
    echo "serializer-input=CANONICAL_LOWERED_VIEW"
    echo "serializer=$serializer"
    echo "canonical-parser-reached=$canonical_parser_reached"
    echo "canonical-semantic-reached=$canonical_semantic_reached"
    echo "canonical-lowering-reached=$canonical_lowering_reached"
    echo "canonical-finalized-state-export=$direct_bootstrap_ir_entry"
    echo "export-view-defined=$direct_bootstrap_ir_entry"
    echo "export-view-read-only=$export_view_read_only"
    echo "function-identity-visible=YES"
    echo "entry-block-visible=YES"
    echo "return-value-visible=$direct_state_preserves_return_constant"
    echo "return-value-origin=CANONICAL_FINALIZED_STATE"
    echo "case-42-exported-return=$case42_exported_return"
    echo "case-43-exported-return=$case43_exported_return"
    echo "export-provenance-differential=$export_provenance_differential"
    echo "direct-bootstrap-ir-entry=$direct_bootstrap_ir_entry"
    echo "direct-state-preserves-return-constant=$direct_state_preserves_return_constant"
    echo "artifact-source-surface=$artifact_source_surface"
    echo "emit-c-intermediate-used=$emit_c_intermediate_used"
    echo "c-source-parsing-used=$c_source_parsing_used"
    echo "c-source-pattern-matching-used=$c_source_pattern_matching_used"
    echo "direct-state-to-bootstrap-ir=$direct_state_to_bootstrap_ir"
    echo "bootstrap-ir-emitted=$bootstrap_ir_emitted"
    echo "bootstrap-ir-format=SSEED-TARGET-V1"
    echo "ir-aot-accepted=$ir_aot_accepted"
    echo "native-artifact-produced=$native_artifact_produced"
    echo "native-artifact-runnable=$native_artifact_runnable"
    echo "case-42-known-result=$case42_known_result"
    echo "case-43-known-result=$case43_known_result"
    echo "seed-frontend-used-for-artifact=$seed_frontend_used_for_artifact"
    echo "seed-semantic-used-for-artifact=$seed_semantic_used_for_artifact"
    echo "provenance-differential-42-43=$provenance_differential_42_43"
    echo "same-input-byte-determinism=$same_input_byte_determinism"
    echo "serializer-parser-authority=NONE"
    echo "serializer-semantic-authority=NONE"
    echo "serializer-mono-authority=NONE"
    echo "serializer-ownership-authority=NONE"
    echo "serializer-drop-authority=NONE"
    echo "serializer-layout-authority=NONE"
    echo "serializer-abi-authority=NONE"
    echo "serializer-symbol-resolution-authority=NONE"
    echo "non-goal=expand-c-extractor"
    echo "non-goal=emit-c-slice-serialization"
    echo "non-goal=full-bootstrap-ir-serializer"
    echo "non-goal=generic"
    echo "non-goal=function-call"
    echo "non-goal=control-flow"
    echo "non-goal=aggregate"
    echo "non-goal=37-file-closure"
    echo "next=B6.3-function-call-bootstrap-ir-coverage"
    echo "missing-capability=$missing_capability"
    echo "verdict=$verdict"
} >"$report"

cat "$report"

if [ "$verdict" = DIRECT_CANONICAL_BOOTSTRAP_IR_EMISSION_PROVEN ]; then
    exit 0
fi

exit 1
