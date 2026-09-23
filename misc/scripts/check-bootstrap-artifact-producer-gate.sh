#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
entry_rel="src/cmd/compile/modular_build_main.s"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
report="${BOOTSTRAP_ARTIFACT_PRODUCER_GATE_REPORT:-"$root/.bootstrap/modular/bootstrap-artifact-producer-gate.txt"}"

bootstrap_ir_generator="${CANONICAL_STAGE1_BOOTSTRAP_IR_GENERATOR:-"$root/src/cmd/compile/bootstrap/generate_bootstrap_ir.sh"}"
bootstrap_ir="${CANONICAL_STAGE1_BOOTSTRAP_IR:-"$root/src/cmd/compile/bootstrap/bootstrap.ir"}"
bootstrap_ir_manifest="${CANONICAL_STAGE1_BOOTSTRAP_MANIFEST:-"$root/src/cmd/compile/bootstrap/bootstrap.manifest"}"
generated_c_producer="${CANONICAL_STAGE1_C_PRODUCER:-"$root/src/cmd/compile/bootstrap/generate_stage1_c.sh"}"
generated_c="${CANONICAL_STAGE1_GENERATED_C:-"$root/src/cmd/compile/bootstrap/stage1.c"}"
generated_c_manifest="${CANONICAL_STAGE1_C_MANIFEST:-"$root/src/cmd/compile/bootstrap/stage1-c.manifest"}"

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

manifest_field() {
    local manifest="$1"
    local key="$2"
    if [ -f "$manifest" ]; then
        awk -F= -v key="$key" '$1 == key { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$manifest"
    else
        echo "NONE"
    fi
}

closure_count=0
canonical_snapshot=NOT_FOUND
canonical_snapshot_contains_entry=NO
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if [ "$closure_count" -gt 0 ] && grep -qx "$entry_rel" "$closure"; then
        canonical_snapshot=FOUND
        canonical_snapshot_contains_entry=YES
    fi
fi

ir_consumer_sseed_ir_to_aot=NOT_PROVEN
if has_text 'emit_aot_from_ir_file|emit_native_from_ir_file|--emit-aot' src/cmd/compile/seed; then
    ir_consumer_sseed_ir_to_aot=PROVEN
fi

c_consumer_generated_c_to_host_cc=UNAVAILABLE
if command -v cc >/dev/null 2>&1; then
    c_consumer_generated_c_to_host_cc=AVAILABLE
fi

seed_ir_producer_exists=$(status_bool has_text 'void generate_code\(IR \*ir, FILE \*output\)|SSEED-TARGET-V1|seed_compile_source_text|semantic_analyze' src/cmd/compile/seed)
seed_ir_duplicates_semantic_authority=YES
seed_ir_verdict=REJECT

selfhost_artifact_exists=NO
if [ -f "$root/.bootstrap/selfhost/stage1.ir" ] || [ -f "$root/.bootstrap/selfhost/stage2.ir" ]; then
    selfhost_artifact_exists=YES
fi
selfhost_artifact_verdict=REFERENCE_ONLY

direct_seed_closure_status=NOT_RUN
direct_seed_closure_diagnostic=NONE
direct_seed_closure_origin=UNKNOWN
direct_seed_single_file_status=NOT_RUN
direct_seed_single_file_diagnostic=NONE
direct_seed_blocker_kind=UNKNOWN
if [ -x "$root/bin/s_seed" ] && [ -f "$closure" ]; then
    direct_seed_tmp="${TMPDIR:-/tmp}/s-direct-seed-closure.$$"
    direct_seed_log="$direct_seed_tmp.log"
    if "$root/bin/s_seed" --closure-compile --source-root "$root" --closure "$closure" "$entry_rel" "$direct_seed_tmp.ir" >"$direct_seed_log" 2>&1; then
        direct_seed_closure_status=UNEXPECTED_PASS
    else
        direct_seed_closure_status=FAIL
        direct_seed_closure_diagnostic=$(sed -n '1p' "$direct_seed_log" | sed 's/[[:cntrl:]]//g')
        direct_seed_line=$(printf '%s\n' "$direct_seed_closure_diagnostic" | sed -n 's/.* at \([0-9][0-9]*\):\([0-9][0-9]*\)\(:.*\| .*\)/\1/p')
        direct_seed_col=$(printf '%s\n' "$direct_seed_closure_diagnostic" | sed -n 's/.* at \([0-9][0-9]*\):\([0-9][0-9]*\)\(:.*\| .*\)/\2/p')
        if [ -n "$direct_seed_line" ] && [ -n "$direct_seed_col" ]; then
            direct_seed_origin=$(awk -v target="$direct_seed_line" -v col="$direct_seed_col" '
                BEGIN { cum = 0 }
                {
                    file = $0
                    cmd = "wc -l < \"" file "\""
                    cmd | getline lines
                    close(cmd)
                    start = cum + 1
                    end = cum + lines
                    if (target >= start && target <= end) {
                        print file ":" (target - cum) ":" col
                        exit
                    }
                    cum = end + 1
                }
            ' "$closure")
            direct_seed_closure_origin=${direct_seed_origin:-UNKNOWN}
            if [ "$direct_seed_closure_origin" != UNKNOWN ]; then
                direct_seed_file=${direct_seed_closure_origin%%:*}
                direct_seed_probe_ir="$direct_seed_tmp.single.ir"
                direct_seed_probe_log="$direct_seed_tmp.single.log"
                if "$root/bin/s_seed" "$root/$direct_seed_file" "$direct_seed_probe_ir" >"$direct_seed_probe_log" 2>&1; then
                    direct_seed_single_file_status=UNEXPECTED_PASS
                else
                    direct_seed_single_file_status=FAIL
                    direct_seed_single_file_diagnostic=$(sed -n '1p' "$direct_seed_probe_log" | sed 's/[[:cntrl:]]//g')
                fi
                if printf '%s\n' "$direct_seed_single_file_diagnostic" | grep -q 'illegal character: |'; then
                    direct_seed_blocker_kind=CANONICAL_SYNTAX_SEED_LEXER_GAP_SINGLE_PIPE
                elif printf '%s\n' "$direct_seed_single_file_diagnostic" | grep -Eq "expected expression, got :|near ':'"; then
                    direct_seed_blocker_kind=CANONICAL_SYNTAX_SEED_PARSER_GAP_STRUCT_FIELD_INITIALIZER
                fi
            fi
        fi
    fi
    rm -f "$direct_seed_tmp.ir" "$direct_seed_log" "$direct_seed_tmp.single.ir" "$direct_seed_tmp.single.log"
fi

ir_producer_exists=NO
ir_producer_non_circular=NOT_PROVEN
ir_producer_bounded=NOT_PROVEN
ir_producer_canonical_semantics=NOT_PROVEN
ir_producer_deterministic=NOT_PROVEN
ir_producer_status=REJECTED

if [ -f "$bootstrap_ir_generator" ] && [ -f "$bootstrap_ir" ] && [ -f "$bootstrap_ir_manifest" ]; then
    ir_producer_exists=YES
    if [ "$(exec_bool "$bootstrap_ir_generator")" = YES ] && \
       has_text 'canonical-closure|STAGE0_CLOSURE|source_closure|modular_build_main\.s' "${bootstrap_ir_generator#"$root/"}" && \
       ! has_text 's_modular-stage1|stage1.*bootstrap\.ir|bootstrap\.ir.*stage1' "${bootstrap_ir_generator#"$root/"}"; then
        ir_producer_non_circular=PROVEN
    fi
    if [ "$(manifest_field "$bootstrap_ir_manifest" bootstrap-artifact-kind)" = SSEED_IR ] && \
       [ "$(manifest_field "$bootstrap_ir_manifest" canonical-closure-count)" = "$closure_count" ]; then
        ir_producer_bounded=PROVEN
    fi
    if [ "$(manifest_field "$bootstrap_ir_manifest" canonical-semantics)" = YES ]; then
        ir_producer_canonical_semantics=PROVEN
    fi
    if [ "$(manifest_field "$bootstrap_ir_manifest" deterministic)" = YES ]; then
        ir_producer_deterministic=PROVEN
    fi
fi

if [ "$ir_producer_exists" = YES ] && \
   [ "$ir_producer_non_circular" = PROVEN ] && \
   [ "$ir_producer_bounded" = PROVEN ] && \
   [ "$ir_producer_canonical_semantics" = PROVEN ] && \
   [ "$ir_producer_deterministic" = PROVEN ]; then
    ir_producer_status=ACCEPTED
fi

c_producer_exists=NO
c_producer_non_circular=NOT_PROVEN
c_producer_bounded=NOT_PROVEN
c_producer_canonical_semantics=NOT_PROVEN
c_producer_deterministic=NOT_PROVEN
c_producer_status=REJECTED

historical_emit_c_exists=$(status_bool has_text '--emit-c|compiler_emit_c|emit_selfhost_c|compile_selfhost_c' src/cmd/compile/compiler.s src/cmd/compile/selfhost/compiler.s makefile)
historical_emit_c_verdict=REFERENCE_ONLY

if [ -f "$generated_c_producer" ] && [ -f "$generated_c" ] && [ -f "$generated_c_manifest" ]; then
    c_producer_exists=YES
    if [ "$(exec_bool "$generated_c_producer")" = YES ] && \
       has_text 'canonical-closure|STAGE0_CLOSURE|source_closure|modular_build_main\.s' "${generated_c_producer#"$root/"}" && \
       ! has_text 's_modular-stage1|stage1.*stage1\.c|stage1\.c.*stage1' "${generated_c_producer#"$root/"}"; then
        c_producer_non_circular=PROVEN
    fi
    if [ "$(manifest_field "$generated_c_manifest" bootstrap-artifact-kind)" = GENERATED_C ] && \
       [ "$(manifest_field "$generated_c_manifest" canonical-closure-count)" = "$closure_count" ]; then
        c_producer_bounded=PROVEN
    fi
    if [ "$(manifest_field "$generated_c_manifest" canonical-semantics)" = YES ]; then
        c_producer_canonical_semantics=PROVEN
    fi
    if [ "$(manifest_field "$generated_c_manifest" deterministic)" = YES ]; then
        c_producer_deterministic=PROVEN
    fi
fi

if [ "$c_producer_exists" = YES ] && \
   [ "$c_producer_non_circular" = PROVEN ] && \
   [ "$c_producer_bounded" = PROVEN ] && \
   [ "$c_producer_canonical_semantics" = PROVEN ] && \
   [ "$c_producer_deterministic" = PROVEN ]; then
    c_producer_status=ACCEPTED
fi

selected_root=NONE
gate=RED
if [ "$ir_producer_status" = ACCEPTED ]; then
    selected_root=SSEED_IR
    gate=GREEN
elif [ "$c_producer_status" = ACCEPTED ]; then
    selected_root=GENERATED_C
    gate=GREEN
fi

{
    echo "P0.BOOTSTRAP_ARTIFACT_PRODUCER_GATE"
    echo "BOOTSTRAP_ARTIFACT_PRODUCER_GATE=$gate"
    echo
    echo "canonical-snapshot=$canonical_snapshot"
    echo "canonical-snapshot-path=$closure"
    echo "canonical-snapshot-count=$closure_count"
    echo "canonical-snapshot-contains-entry=$canonical_snapshot_contains_entry"
    echo
    echo "ir-producer:"
    echo "  exists=$ir_producer_exists"
    echo "  non-circular=$ir_producer_non_circular"
    echo "  bounded=$ir_producer_bounded"
    echo "  canonical-semantics=$ir_producer_canonical_semantics"
    echo "  deterministic=$ir_producer_deterministic"
    echo "  status=$ir_producer_status"
    echo
    echo "ir-consumer:"
    echo "  SSEED_IR_TO_AOT=$ir_consumer_sseed_ir_to_aot"
    echo
    echo "c-producer:"
    echo "  exists=$c_producer_exists"
    echo "  non-circular=$c_producer_non_circular"
    echo "  bounded=$c_producer_bounded"
    echo "  canonical-semantics=$c_producer_canonical_semantics"
    echo "  deterministic=$c_producer_deterministic"
    echo "  status=$c_producer_status"
    echo
    echo "c-consumer:"
    echo "  GENERATED_C_TO_HOST_CC=$c_consumer_generated_c_to_host_cc"
    echo
    echo "rejected-or-reference-producers:"
    echo "  seed-ir-producer-exists=$seed_ir_producer_exists"
    echo "  seed-ir-duplicates-semantic-authority=$seed_ir_duplicates_semantic_authority"
    echo "  seed-ir-verdict=$seed_ir_verdict"
    echo "  historical-emit-c-exists=$historical_emit_c_exists"
    echo "  historical-emit-c-verdict=$historical_emit_c_verdict"
    echo "  selfhost-artifact-exists=$selfhost_artifact_exists"
    echo "  selfhost-artifact-verdict=$selfhost_artifact_verdict"
    echo "  direct-seed-closure-status=$direct_seed_closure_status"
    echo "  direct-seed-closure-diagnostic=$direct_seed_closure_diagnostic"
    echo "  direct-seed-closure-origin=$direct_seed_closure_origin"
    echo "  direct-seed-single-file-status=$direct_seed_single_file_status"
    echo "  direct-seed-single-file-diagnostic=$direct_seed_single_file_diagnostic"
    echo "  direct-seed-blocker-kind=$direct_seed_blocker_kind"
    echo
    echo "selected-root=$selected_root"
    echo
    echo "first-missing-edge="
    echo "  canonical snapshot"
    echo "  -> deterministic canonical Stage1 artifact"
    echo
    echo "G1_PRODUCER=$gate"
    echo "G2_AUTHORITY=NOT_RUN"
    echo "G3_REGENERATION=NOT_RUN"
    echo
    echo "DIRECT_SEED_CLOSURE=REJECTED"
    echo "DIRECT_SEED_CLOSURE_STATUS=$direct_seed_closure_status"
    echo "DIRECT_SEED_BLOCKER_KIND=$direct_seed_blocker_kind"
    echo "SEED_REASSIGNMENT_FIX=FORBIDDEN_BY_CURRENT_GATE"
} | tee "$report"

[ "$gate" = GREEN ]
