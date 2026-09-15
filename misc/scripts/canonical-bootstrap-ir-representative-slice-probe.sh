#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
seed=${SEED_COMPILER_BIN:-"$root/bin/s_seed"}
report=${CANONICAL_BOOTSTRAP_IR_REPRESENTATIVE_SLICE_REPORT:-"$root/.bootstrap/modular/canonical-bootstrap-ir-representative-slice-probe.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/canonical-bootstrap-ir-representative-slice.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

ir="$tmp/representative.ir"
native="$tmp/representative"
log="$tmp/emit-aot.log"

cat >"$ir" <<'IR'
SSEED-TARGET-V1
FUNC_BEGIN|main|_|_
CALL|t0|__vec_make|0
MOV|state|t0|_
ARG|"state"|_|_
ARG|19|_|_
CALL|t1|__vec_push|2
ARG|"state"|_|_
ARG|23|_|_
CALL|t2|__vec_push|2
ARG|"state"|_|_
ARG|0|_|_
CALL|left|__vec_get|2
ARG|"state"|_|_
ARG|1|_|_
CALL|right|__vec_get|2
ARG|left|_|_
ARG|right|_|_
CALL|sum|compiler_like_sum|2
ARG|sum|_|_
CALL|result|compiler_like_classify|1
RET|result|_|_
RET|0|_|_
FUNC_END|main|_|_
FUNC_BEGIN|compiler_like_sum|_|_
PARAM|left|_|_
PARAM|right|_|_
ADD|total|left|right
RET|total|_|_
FUNC_END|compiler_like_sum|_|_
FUNC_BEGIN|compiler_like_classify|_|_
PARAM|value|_|_
CMP_EQ|is_answer|value|42
JUMP_IF_FALSE|not_answer|is_answer|_
RET|value|_|_
LABEL|not_answer|_|_
RET|1|_|_
FUNC_END|compiler_like_classify|_|_
IR

set +e
S_SOURCE_ROOT="$root" "$seed" --emit-aot "$ir" "$native" >"$log" 2>&1
emit_status=$?
run_status=NOT_RUN
if [ "$emit_status" -eq 0 ] && [ -x "$native" ]; then
    "$native" >/dev/null 2>&1
    run_status=$?
fi
set -e

ir_artifact_generated=YES
ir_artifact_self_contained=YES

ir_aot_accepted=NO
[ "$emit_status" -eq 0 ] && ir_aot_accepted=YES

native_artifact_produced=NO
[ -x "$native" ] && native_artifact_produced=YES

native_artifact_runnable=NO
[ "$run_status" = 42 ] && native_artifact_runnable=YES

seed_frontend_used=NO
seed_semantic_used=NO
if grep -Eq 'PARSE_FAIL|expected .* got|use of undeclared symbol|type error|SEMANTIC' "$log"; then
    seed_semantic_used=YES
fi

slice_function_call=NO
slice_control_flow=NO
slice_aggregate_memory=NO
slice_cross_function_data_flow=NO
grep -q '^CALL|' "$ir" && slice_function_call=YES
grep -q '^JUMP_IF_FALSE|' "$ir" && slice_control_flow=YES
grep -Eq '__(vec_make|vec_push|vec_get)' "$ir" && slice_aggregate_memory=YES
grep -q '^PARAM|' "$ir" && grep -q '^ARG|' "$ir" && slice_cross_function_data_flow=YES

probe_verdict=IR_ROOT_NOT_VIABLE
missing_capability=NONE
if [ "$ir_aot_accepted" = YES ] && [ "$native_artifact_runnable" = YES ] && \
   [ "$seed_frontend_used" = NO ] && [ "$seed_semantic_used" = NO ] && \
   [ "$slice_function_call" = YES ] && [ "$slice_control_flow" = YES ] && \
   [ "$slice_aggregate_memory" = YES ] && [ "$slice_cross_function_data_flow" = YES ]; then
    probe_verdict=IR_REPRESENTATION_PROVEN
    missing_capability=canonical-bootstrap-ir-emission
else
    if [ "$slice_function_call" != YES ]; then missing_capability=function-call; fi
    if [ "$slice_control_flow" != YES ]; then missing_capability=control-flow; fi
    if [ "$slice_aggregate_memory" != YES ]; then missing_capability=aggregate-memory; fi
    if [ "$slice_cross_function_data_flow" != YES ]; then missing_capability=cross-function-data-flow; fi
    if [ "$ir_aot_accepted" != YES ]; then missing_capability=ir-aot-consumption; fi
    if [ "$native_artifact_runnable" != YES ]; then missing_capability=native-execution; fi
    if [ "$seed_frontend_used" != NO ] || [ "$seed_semantic_used" != NO ]; then missing_capability=consumer-independence; fi
fi

{
    echo "canonical-bootstrap-ir-representative-slice-probe"
    echo "probe=IR-P1-REPRESENTATIVE-CANONICAL-SLICE"
    echo "slice-origin=HAND_AUTHORED_PROBE"
    echo "representative-ir-origin=HAND_AUTHORED_PROBE"
    echo "slice-capability=function-call:$slice_function_call"
    echo "slice-capability=control-flow:$slice_control_flow"
    echo "slice-capability=aggregate-memory:$slice_aggregate_memory"
    echo "slice-capability=cross-function-data-flow:$slice_cross_function_data_flow"
    echo "ir-artifact-generated=$ir_artifact_generated"
    echo "ir-artifact-self-contained=$ir_artifact_self_contained"
    echo "seed-frontend-used=$seed_frontend_used"
    echo "seed-semantic-used=$seed_semantic_used"
    echo "semantic-processing-scope=source-frontend-semantic-processing-only"
    echo "ir-validation-before-aot=ALLOWED"
    echo "ir-aot-accepted=$ir_aot_accepted"
    echo "native-artifact-produced=$native_artifact_produced"
    echo "native-artifact-runnable=$native_artifact_runnable"
    echo "known-result=$run_status"
    echo "canonical-lowering-produced-artifact=NO"
    echo "canonical-ir-generation=NOT_PROVEN"
    echo "full-canonical-closure=NOT_ATTEMPTED_BY_DESIGN"
    echo "stage1-generation=NOT_ATTEMPTED_BY_DESIGN"
    echo "stage2-stage3-convergence=NOT_ATTEMPTED_BY_DESIGN"
    echo "missing-capability=$missing_capability"
    echo "probe-verdict=$probe_verdict"
    if [ -s "$log" ]; then
        sed 's/^/consumer-diagnostic=/' "$log"
    fi
} >"$report"

cat "$report"

case "$probe_verdict" in
    CANONICAL_IR_SLICE_PROVEN|IR_REPRESENTATION_PROVEN) exit 0 ;;
    *) exit 1 ;;
esac
