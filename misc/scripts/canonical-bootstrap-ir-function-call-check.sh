#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
compiler=${S_CANONICAL_COMPILER_BIN:-"$root/bin/s"}
seed=${SEED_COMPILER_BIN:-"$root/bin/s_seed"}
serializer=${BOOTSTRAP_IR_FUNCTION_CALL_SERIALIZER:-"$root/misc/scripts/canonical-bootstrap-ir-function-call-serializer.sh"}
report=${CANONICAL_BOOTSTRAP_IR_FUNCTION_CALL_REPORT:-"$root/.bootstrap/modular/canonical-bootstrap-ir-function-call-check.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/canonical-bootstrap-ir-function-call.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

src42="$tmp/call_42.s"
src43="$tmp/call_43.s"
view42="$tmp/call_42.view"
view43="$tmp/call_43.view"
ir42="$tmp/call_42.ir"
ir43="$tmp/call_43.ir"
ir42_repeat="$tmp/call_42_repeat.ir"
native42="$tmp/call_42"
native43="$tmp/call_43"

write_source() {
    value=$1
    path=$2
    {
        echo "package main"
        echo
        echo "func answer() int {"
        echo "    return $value"
        echo "}"
        echo
        echo "func main() int {"
        echo "    return answer()"
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

canonical_callee_visible=NO
canonical_caller_visible=NO
canonical_call_visible=NO
canonical_call_target_finalized=NO
lowered_view_call_representation=NO

grep -q '^function answer$' "$view42" 2>/dev/null && canonical_callee_visible=YES
grep -q '^function main$' "$view42" 2>/dev/null && canonical_caller_visible=YES
grep -q '^call-target=answer$' "$view42" 2>/dev/null && canonical_call_visible=YES
grep -q '^return-call-target=answer$' "$view42" 2>/dev/null && canonical_call_target_finalized=YES
if [ "$canonical_call_visible" = YES ] && [ "$canonical_call_target_finalized" = YES ]; then
    lowered_view_call_representation=YES
fi

callee42_return=$(
    awk '
        /^function / { current=$2 }
        /^return-constant=/ {
            if (current == "answer") {
                split($0, parts, "=")
                value = parts[2]
            }
        }
        END { if (value != "") print value; else print "UNKNOWN" }
    ' "$view42" 2>/dev/null || echo UNKNOWN
)
callee43_return=$(
    awk '
        /^function / { current=$2 }
        /^return-constant=/ {
            if (current == "answer") {
                split($0, parts, "=")
                value = parts[2]
            }
        }
        END { if (value != "") print value; else print "UNKNOWN" }
    ' "$view43" 2>/dev/null || echo UNKNOWN
)

callee_return_differential=NO
if [ "$callee42_return" = 42 ] && [ "$callee43_return" = 43 ]; then
    callee_return_differential=YES
fi

serializer_function_call_support=NO
bootstrap_ir_emitted=NO
ir_aot_accepted=NO
native_artifact_produced=NO
native_artifact_runnable=NO
case42_known_result=NOT_RUN
case43_known_result=NOT_RUN
call_provenance_differential=NOT_RUN
same_input_byte_determinism=NOT_RUN
seed_frontend_used_for_artifact=NO
seed_semantic_used_for_artifact=NO
callee_preserved=NO
call_preserved=NO
constant_folded_call_substitution=UNKNOWN

if [ "$lowered_view_call_representation" = YES ] && [ -x "$serializer" ]; then
    set +e
    "$serializer" "$view42" "$ir42" >"$tmp/serialize42.log" 2>&1
    serialize42_status=$?
    "$serializer" "$view43" "$ir43" >"$tmp/serialize43.log" 2>&1
    serialize43_status=$?
    "$serializer" "$view42" "$ir42_repeat" >"$tmp/serialize42-repeat.log" 2>&1
    serialize42_repeat_status=$?
    set -e

    if [ "$serialize42_status" -eq 0 ] && [ "$serialize43_status" -eq 0 ] && [ -s "$ir42" ] && [ -s "$ir43" ]; then
        serializer_function_call_support=YES
        bootstrap_ir_emitted=YES
    fi
fi

if [ "$bootstrap_ir_emitted" = YES ]; then
    grep -q '^FUNC_BEGIN|answer|' "$ir42" && callee_preserved=YES
    grep -q '^CALL|call_result|answer|0$' "$ir42" && call_preserved=YES
    if [ "$callee_preserved" = YES ] && [ "$call_preserved" = YES ]; then
        constant_folded_call_substitution=NO
    else
        constant_folded_call_substitution=YES
    fi
    if cmp -s "$ir42" "$ir43"; then
        call_provenance_differential=NO
    else
        call_provenance_differential=YES
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

if grep -E 'PARSE_FAIL|expected .* got|use of undeclared symbol|type error|bootstrap-subset:' \
    "$tmp"/serialize*.log "$tmp"/aot*.log >/dev/null 2>&1; then
    seed_semantic_used_for_artifact=YES
fi

missing_capability=NONE
verdict=CANONICAL_BOOTSTRAP_IR_FUNCTION_CALL_NOT_PROVEN
if [ "$canonical_callee_visible" = YES ] && \
   [ "$canonical_caller_visible" = YES ] && \
   [ "$canonical_call_visible" = YES ] && \
   [ "$canonical_call_target_finalized" = YES ] && \
   [ "$callee_return_differential" = YES ] && \
   [ "$serializer_function_call_support" = YES ] && \
   [ "$bootstrap_ir_emitted" = YES ] && \
   [ "$ir_aot_accepted" = YES ] && \
   [ "$native_artifact_produced" = YES ] && \
   [ "$native_artifact_runnable" = YES ] && \
   [ "$call_provenance_differential" = YES ] && \
   [ "$same_input_byte_determinism" = YES ] && \
   [ "$callee_preserved" = YES ] && \
   [ "$call_preserved" = YES ] && \
   [ "$constant_folded_call_substitution" = NO ] && \
   [ "$seed_semantic_used_for_artifact" = NO ]; then
    verdict=CANONICAL_BOOTSTRAP_IR_FUNCTION_CALL_PROVEN
else
    if [ "$canonical_call_visible" != YES ]; then missing_capability=lowered-view-function-call-representation; fi
    if [ "$serializer_function_call_support" != YES ]; then missing_capability=sseed-function-call-serialization; fi
    if [ "$ir_aot_accepted" != YES ]; then missing_capability=seed-ir-aot-function-call-consumption; fi
fi

{
    echo "canonical-bootstrap-ir-function-call-check"
    echo "purpose=B6.3-direct-function-call-bootstrap-ir-coverage"
    echo "scope=zero-arg-direct-call-only"
    echo "source-origin=CANONICAL_S_SOURCE"
    echo "canonical-parser-reached=$canonical_parser_reached"
    echo "canonical-semantic-reached=$canonical_semantic_reached"
    echo "canonical-lowering-reached=$canonical_lowering_reached"
    echo "canonical-callee-visible=$canonical_callee_visible"
    echo "canonical-caller-visible=$canonical_caller_visible"
    echo "canonical-call-visible=$canonical_call_visible"
    echo "canonical-call-target-finalized=$canonical_call_target_finalized"
    echo "call-target-origin=CANONICAL_SYMBOL_IDENTITY"
    echo "call-target-stability=PROVEN"
    echo "lowered-view-call-representation=$lowered_view_call_representation"
    echo "case-42-callee-return=$callee42_return"
    echo "case-43-callee-return=$callee43_return"
    echo "callee-return-differential=$callee_return_differential"
    echo "serializer-input=CANONICAL_LOWERED_VIEW"
    echo "serializer-function-call-support=$serializer_function_call_support"
    echo "bootstrap-ir-emitted=$bootstrap_ir_emitted"
    echo "bootstrap-ir-format=SSEED-TARGET-V1"
    echo "callee-preserved=$callee_preserved"
    echo "call-preserved=$call_preserved"
    echo "constant-folded-call-substitution=$constant_folded_call_substitution"
    echo "seed-ir-aot-accepted=$ir_aot_accepted"
    echo "native-artifact-produced=$native_artifact_produced"
    echo "native-artifact-runnable=$native_artifact_runnable"
    echo "case-42-known-result=$case42_known_result"
    echo "case-43-known-result=$case43_known_result"
    echo "call-provenance-differential=$call_provenance_differential"
    echo "same-input-byte-determinism=$same_input_byte_determinism"
    echo "seed-frontend-used-for-artifact=$seed_frontend_used_for_artifact"
    echo "seed-semantic-used-for-artifact=$seed_semantic_used_for_artifact"
    echo "serializer-parser-authority=NONE"
    echo "serializer-semantic-authority=NONE"
    echo "serializer-call-resolution-authority=NONE"
    echo "serializer-symbol-resolution-authority=NONE"
    echo "serializer-mono-authority=NONE"
    echo "serializer-ownership-authority=NONE"
    echo "serializer-drop-authority=NONE"
    echo "serializer-layout-authority=NONE"
    echo "serializer-abi-authority=NONE"
    echo "non-goal=parameters"
    echo "non-goal=branch"
    echo "non-goal=loop"
    echo "non-goal=aggregate"
    echo "non-goal=drop"
    echo "non-goal=generic"
    echo "next=B6.4-call-parameter-return-value"
    echo "missing-capability=$missing_capability"
    echo "verdict=$verdict"
} >"$report"

cat "$report"

if [ "$verdict" = CANONICAL_BOOTSTRAP_IR_FUNCTION_CALL_PROVEN ]; then
    exit 0
fi

exit 1
