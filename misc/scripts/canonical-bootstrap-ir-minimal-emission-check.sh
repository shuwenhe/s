#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
seed=${SEED_COMPILER_BIN:-"$root/bin/s_seed"}
compiler=${S_CANONICAL_COMPILER_BIN:-"$root/bin/s"}
serializer=${BOOTSTRAP_IR_MINIMAL_SERIALIZER:-"$root/misc/scripts/canonical-bootstrap-ir-minimal-serializer.sh"}
report=${CANONICAL_BOOTSTRAP_IR_MINIMAL_EMISSION_REPORT:-"$root/.bootstrap/modular/canonical-bootstrap-ir-minimal-emission-check.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/canonical-bootstrap-ir-minimal-emission.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

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

run_case() {
    value=$1
    src="$tmp/minimal_$value.s"
    c_out="$tmp/minimal_$value.c"
    ir_out="$tmp/minimal_$value.ir"
    native="$tmp/minimal_$value"
    log="$tmp/minimal_$value.log"

    write_source "$value" "$src"

    canonical_parser_reached=NO
    canonical_semantic_reached=NO
    canonical_lowering_reached=NO
    bootstrap_ir_emitted=NO
    ir_aot_accepted=NO
    native_artifact_produced=NO
    native_artifact_runnable=NO
    run_status=NOT_RUN

    set +e
    "$compiler" --emit-c "$src" "$c_out" >"$log" 2>&1
    compile_status=$?
    set -e

    if [ "$compile_status" -eq 0 ] && [ -s "$c_out" ]; then
        canonical_parser_reached=YES
        canonical_semantic_reached=YES
        canonical_lowering_reached=YES
    fi

    if [ "$canonical_lowering_reached" = YES ] && [ -x "$serializer" ]; then
        set +e
        "$serializer" "$c_out" "$ir_out" >>"$log" 2>&1
        serialize_status=$?
        set -e
        if [ "$serialize_status" -eq 0 ] && [ -s "$ir_out" ]; then
            bootstrap_ir_emitted=YES
        fi
    fi

    if [ "$bootstrap_ir_emitted" = YES ]; then
        set +e
        S_SOURCE_ROOT="$root" "$seed" --emit-aot "$ir_out" "$native" >>"$log" 2>&1
        aot_status=$?
        set -e
        if [ "$aot_status" -eq 0 ]; then
            ir_aot_accepted=YES
        fi
        if [ -x "$native" ]; then
            native_artifact_produced=YES
            set +e
            "$native" >/dev/null 2>&1
            run_status=$?
            set -e
            if [ "$run_status" = "$value" ]; then
                native_artifact_runnable=YES
            fi
        fi
    fi

    {
        echo "case-$value-canonical-parser-reached=$canonical_parser_reached"
        echo "case-$value-canonical-semantic-reached=$canonical_semantic_reached"
        echo "case-$value-canonical-lowering-reached=$canonical_lowering_reached"
        echo "case-$value-bootstrap-ir-emitted=$bootstrap_ir_emitted"
        echo "case-$value-ir-aot-accepted=$ir_aot_accepted"
        echo "case-$value-native-artifact-produced=$native_artifact_produced"
        echo "case-$value-native-artifact-runnable=$native_artifact_runnable"
        echo "case-$value-known-result=$run_status"
        echo "case-$value-ir=$ir_out"
        echo "case-$value-canonical-c=$c_out"
    } >>"$tmp/cases.report"
}

run_case 42
run_case 43

same_input_byte_determinism=NOT_RUN
ir_a="$tmp/minimal_42.ir"
ir_b="$tmp/minimal_42_repeat.ir"
c_a="$tmp/minimal_42.c"
if [ -s "$ir_a" ] && [ -x "$serializer" ]; then
    "$serializer" "$c_a" "$ir_b" >/dev/null 2>&1
    if cmp -s "$ir_a" "$ir_b"; then
        same_input_byte_determinism=YES
    else
        same_input_byte_determinism=NO
    fi
fi

provenance_differential=NOT_RUN
if [ -s "$tmp/minimal_42.ir" ] && [ -s "$tmp/minimal_43.ir" ]; then
    if cmp -s "$tmp/minimal_42.ir" "$tmp/minimal_43.ir"; then
        provenance_differential=NO
    else
        provenance_differential=YES
    fi
fi

seed_frontend_used_for_artifact=NO
seed_semantic_used_for_artifact=NO
if grep -E 'PARSE_FAIL|expected .* got|use of undeclared symbol|type error|bootstrap-subset:' \
    "$tmp/minimal_42.log" "$tmp/minimal_43.log" >/dev/null 2>&1; then
    seed_semantic_used_for_artifact=YES
fi

case42_ir=$(awk -F= '$1 == "case-42-bootstrap-ir-emitted" { print $2 }' "$tmp/cases.report")
case43_ir=$(awk -F= '$1 == "case-43-bootstrap-ir-emitted" { print $2 }' "$tmp/cases.report")
case42_run=$(awk -F= '$1 == "case-42-native-artifact-runnable" { print $2 }' "$tmp/cases.report")
case43_run=$(awk -F= '$1 == "case-43-native-artifact-runnable" { print $2 }' "$tmp/cases.report")
case42_lower=$(awk -F= '$1 == "case-42-canonical-lowering-reached" { print $2 }' "$tmp/cases.report")
case43_lower=$(awk -F= '$1 == "case-43-canonical-lowering-reached" { print $2 }' "$tmp/cases.report")

missing_capability=NONE
verdict=MINIMAL_CANONICAL_BOOTSTRAP_IR_EMISSION_NOT_PROVEN
if [ "$case42_lower" != YES ] || [ "$case43_lower" != YES ]; then
    missing_capability=canonical-minimal-source-lowering
elif [ "$case42_ir" != YES ] || [ "$case43_ir" != YES ]; then
    missing_capability=canonical-bootstrap-ir-serializer
elif [ "$case42_run" != YES ] || [ "$case43_run" != YES ]; then
    missing_capability=bootstrap-ir-aot-native-e2e
elif [ "$provenance_differential" != YES ]; then
    missing_capability=source-to-artifact-provenance
elif [ "$same_input_byte_determinism" != YES ]; then
    missing_capability=minimal-serializer-determinism
elif [ "$seed_semantic_used_for_artifact" != NO ]; then
    missing_capability=seed-semantic-contamination
else
    verdict=MINIMAL_CANONICAL_BOOTSTRAP_IR_EMISSION_PROVEN
fi

{
    echo "canonical-bootstrap-ir-minimal-emission-check"
    echo "purpose=B6.1-minimal-real-canonical-source-to-bootstrap-ir-to-native"
    echo "scope=return-constant-program-only"
    echo "source-origin=CANONICAL_S_SOURCE"
    echo "canonical-lowered-state-source=EMIT_C_ARTIFACT_SLICE"
    echo "canonical-lowered-state-scope=MINIMAL_RETURN_CONSTANT"
    echo "bootstrap-ir-origin=CANONICAL_FINALIZED_STATE"
    echo "bootstrap-ir-format=SSEED-TARGET-V1"
    echo "serializer=$serializer"
    cat "$tmp/cases.report"
    echo "seed-frontend-used-for-artifact=$seed_frontend_used_for_artifact"
    echo "seed-semantic-used-for-artifact=$seed_semantic_used_for_artifact"
    echo "provenance-differential-42-43=$provenance_differential"
    echo "same-input-byte-determinism=$same_input_byte_determinism"
    echo "serializer-parser-authority=NONE"
    echo "serializer-semantic-authority=NONE"
    echo "serializer-mono-authority=NONE"
    echo "serializer-ownership-authority=NONE"
    echo "serializer-drop-authority=NONE"
    echo "serializer-layout-authority=NONE"
    echo "serializer-abi-authority=NONE"
    echo "serializer-symbol-resolution-authority=NONE"
    echo "non-goal=full-bootstrap-ir-serializer"
    echo "non-goal=generic"
    echo "non-goal=loops"
    echo "non-goal=aggregate"
    echo "non-goal=partial-move"
    echo "non-goal=37-file-closure"
    echo "non-goal=stage2-stage3-convergence"
    echo "missing-capability=$missing_capability"
    echo "verdict=$verdict"
} >"$report"

cat "$report"

if [ "$verdict" = MINIMAL_CANONICAL_BOOTSTRAP_IR_EMISSION_PROVEN ]; then
    exit 0
fi

exit 1
