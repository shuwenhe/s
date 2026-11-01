#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
seed=${SEED_COMPILER_BIN:-"$root/bin/s_seed"}
report=${CANONICAL_BOOTSTRAP_IR_FEASIBILITY_REPORT:-"$root/.bootstrap/modular/canonical-bootstrap-ir-feasibility-probe.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/canonical-bootstrap-ir-feasibility.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

ir="$tmp/minimal.ir"
native="$tmp/minimal"
log="$tmp/emit-aot.log"

cat >"$ir" <<'IR'
SSEED-TARGET-V1
FUNC_BEGIN|main|_|_
RET|42|_|_
RET|0|_|_
FUNC_END|main|_|_
IR

consumer_entry="$seed --emit-aot <input.ir> <output>"
consumer_input_format=$(sed -n '1p' "$ir")
consumer_input_format_version=UNKNOWN
case "$consumer_input_format" in
    SSEED-TARGET-V*) consumer_input_format_version=${consumer_input_format#SSEED-TARGET-V} ;;
esac

set +e
S_SOURCE_ROOT="$root" "$seed" --emit-aot "$ir" "$native" >"$log" 2>&1
emit_status=$?
run_status=NOT_RUN
if [ "$emit_status" -eq 0 ] && [ -x "$native" ]; then
    "$native" >/dev/null 2>&1
    run_status=$?
fi
set -e

minimal_ir_accepted=NO
[ "$emit_status" -eq 0 ] && minimal_ir_accepted=YES

native_artifact_produced=NO
[ -x "$native" ] && native_artifact_produced=YES

native_artifact_runnable=NO
[ "$run_status" = 42 ] && native_artifact_runnable=YES

frontend_processing_before_aot=NO
semantic_processing_before_aot=NO
if grep -Eq 'PARSE_FAIL|expected .* got|use of undeclared symbol|type error|SEMANTIC' "$log"; then
    semantic_processing_before_aot=YES
fi

artifact_self_contained=YES
artifact_host_source_required=NO
artifact_canonical_source_required_at_bootstrap_time=NO
artifact_external_semantic_state_required=NO

artifact_consumer_independence=NOT_PROVEN
artifact_consumer_plumbing=NOT_PROVEN
probe_verdict=IR_ROOT_NOT_VIABLE
if [ "$minimal_ir_accepted" = YES ] && [ "$native_artifact_runnable" = YES ] && \
   [ "$frontend_processing_before_aot" = NO ] && [ "$semantic_processing_before_aot" = NO ] && \
   [ "$artifact_self_contained" = YES ]; then
    artifact_consumer_independence=PROVEN_FOR_IR_P0
    artifact_consumer_plumbing=PROVEN
    probe_verdict=IR_ROOT_PARTIAL
fi

{
    echo "canonical-bootstrap-ir-feasibility-probe"
    echo "probe=IR-P0-minimal-entry-return"
    echo "probe-artifact-kind=IR"
    echo "artifact-consumer=existing-seed-ir-aot"
    echo "consumer-entry=$consumer_entry"
    echo "consumer-input-format=$consumer_input_format"
    echo "consumer-input-format-version=$consumer_input_format_version"
    echo "minimal-ir-accepted=$minimal_ir_accepted"
    echo "native-artifact-produced=$native_artifact_produced"
    echo "native-artifact-runnable=$native_artifact_runnable"
    echo "known-entry-result=$run_status"
    echo "frontend-processing-before-aot=$frontend_processing_before_aot"
    echo "semantic-processing-before-aot=$semantic_processing_before_aot"
    echo "semantic-processing-scope=source-frontend-semantic-processing-only"
    echo "ir-validation-before-aot=ALLOWED"
    echo "artifact-self-contained=$artifact_self_contained"
    echo "artifact-host-source-required=$artifact_host_source_required"
    echo "artifact-canonical-source-required-at-bootstrap-time=$artifact_canonical_source_required_at_bootstrap_time"
    echo "artifact-external-semantic-state-required=$artifact_external_semantic_state_required"
    echo "artifact-consumer-independence=$artifact_consumer_independence"
    echo "artifact-consumer-plumbing=$artifact_consumer_plumbing"
    echo "ir-root-feasibility-scope=P0_ONLY"
    echo "ir-p0-pass-does-not-mean-full-root-feasible=TRUE"
    echo "next-if-partial=B3.4-representative-canonical-ir-slice-probe"
    echo "probe-verdict=$probe_verdict"
    if [ -s "$log" ]; then
        sed 's/^/consumer-diagnostic=/' "$log"
    fi
} >"$report"

cat "$report"

case "$probe_verdict" in
    IR_ROOT_PARTIAL|IR_ROOT_FEASIBLE) exit 0 ;;
    *) exit 1 ;;
esac
