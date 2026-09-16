#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
entry_rel="src/cmd/compile/modular_build_main.s"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
report="$root/.bootstrap/modular/b6.7.3e2c-generated-c-producer-audit.txt"

tmp="${TMPDIR:-/tmp}/b6.7.3e2c-generated-c.$$"
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
closure_contains_entry=NO
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if grep -qx "$entry_rel" "$closure"; then
        closure_contains_entry=YES
    fi
fi

canonical_emit_c_capability=$(status_bool has_text '--emit-c|compiler_emit_c|emit_selfhost_c|compile_selfhost_c' src/cmd/compile/compiler.s src/cmd/compile/selfhost/compiler.s makefile)
host_cc_can_consume_output=UNKNOWN
if command -v cc >/dev/null 2>&1; then
    host_cc_can_consume_output=YES
fi

executor=NONE
executor_path=NONE
executor_requires_stage1=UNKNOWN
executor_can_consume_37_file_closure=NO
executor_reaches_canonical_parser=NO
executor_reaches_canonical_semantic=NO
executor_reaches_canonical_lowering=NO
executor_produces_full_stage1_c=NO
executor_output_c=NONE
executor_first_failure=NONE

probe_emit_c() {
    local label="$1"
    local bin="$2"
    local src="$3"
    local out="$4"
    local log="$5"

    if [ ! -x "$bin" ]; then
        echo "MISSING"
        return
    fi
    set +e
    "$bin" --emit-c "$src" "$out" >"$log" 2>&1
    local status=$?
    set -e
    if [ "$status" -eq 0 ] && [ -s "$out" ]; then
        echo "PASS"
    else
        local first
        first=$(sed -n '1p' "$log" 2>/dev/null | tr '\n' ' ')
        echo "FAIL:$first"
    fi
}

probe_build_c_artifact() {
    local label="$1"
    local bin="$2"
    local src="$3"
    local out="$4"
    local log="$5"

    if [ ! -x "$bin" ]; then
        echo "MISSING"
        return
    fi
    set +e
    "$bin" build "$src" -o "$out" >"$log" 2>&1
    local status=$?
    set -e
    if [ "$status" -eq 0 ] && [ -x "$out" ]; then
        echo "PASS"
    else
        local first
        first=$(sed -n '1p' "$log" 2>/dev/null | tr '\n' ' ')
        echo "FAIL:$first"
    fi
}

entry_abs="$root/$entry_rel"
s_compiler_probe=$(probe_emit_c bin-s_compiler "$root/bin/s_compiler" "$entry_abs" "$tmp/s_compiler.stage1.c" "$tmp/s_compiler.log")
s_wrapper_probe=$(probe_emit_c bin-s "$root/bin/s" "$entry_abs" "$tmp/s_wrapper.stage1.c" "$tmp/s_wrapper.log")
stage1_emit_c_probe=$(probe_emit_c modular-stage1 "$root/.bootstrap/modular/s_modular-stage1" "$entry_abs" "$tmp/modular_stage1.stage1.c" "$tmp/modular_stage1_emit_c.log")
stage1_build_probe=$(probe_build_c_artifact modular-stage1-build "$root/.bootstrap/modular/s_modular-stage1" "$entry_abs" "$tmp/modular_stage1_build.out" "$tmp/modular_stage1_build.log")

classify_output_c() {
    local out="$1"
    if [ ! -s "$out" ]; then
        echo "NO_OUTPUT"
        return
    fi
    if rg -q 'modular_build_main|backend_elf64|compile\.internal\.semantic|parse_source|check_source_file' "$out"; then
        echo "CANONICAL_STAGE1_C_CANDIDATE"
        return
    fi
    if rg -q 'compiler_result|S_COMPILER_CHECK_ALLOCATIONS|int main' "$out"; then
        echo "SINGLE_SOURCE_PROGRAM_C"
        return
    fi
    echo "UNKNOWN_C"
}

s_compiler_c_kind=$(classify_output_c "$tmp/s_compiler.stage1.c")
s_wrapper_c_kind=$(classify_output_c "$tmp/s_wrapper.stage1.c")
stage1_emit_c_kind=$(classify_output_c "$tmp/modular_stage1.stage1.c")

if [[ "$s_compiler_probe" == PASS* ]]; then
    executor=bin/s_compiler
    executor_path="$root/bin/s_compiler"
    executor_output_c="$tmp/s_compiler.stage1.c"
    executor_first_failure=NONE
elif [[ "$s_wrapper_probe" == PASS* ]]; then
    executor=bin/s
    executor_path="$root/bin/s"
    executor_output_c="$tmp/s_wrapper.stage1.c"
    executor_first_failure=NONE
elif [[ "$stage1_emit_c_probe" == PASS* ]]; then
    executor=s_modular-stage1
    executor_path="$root/.bootstrap/modular/s_modular-stage1"
    executor_output_c="$tmp/modular_stage1.stage1.c"
    executor_first_failure=NONE
else
    executor_first_failure="$s_compiler_probe"
fi

if [ "$executor" = s_modular-stage1 ]; then
    executor_requires_stage1=YES
elif [ "$executor" != NONE ]; then
    executor_requires_stage1=NO
fi

if [ "$executor" != NONE ]; then
    if [ -s "$executor_output_c" ]; then
        executor_can_consume_37_file_closure=SINGLE_ENTRY_ONLY
        executor_reaches_canonical_parser=UNKNOWN
        executor_reaches_canonical_semantic=UNKNOWN
        executor_reaches_canonical_lowering=UNKNOWN
        if rg -q 'modular_build_main|backend_elf64|compile\.internal\.semantic|parse_source|check_source_file' "$executor_output_c"; then
            executor_can_consume_37_file_closure=YES
            executor_reaches_canonical_parser=YES
            executor_reaches_canonical_semantic=YES
            executor_reaches_canonical_lowering=YES
            executor_produces_full_stage1_c=YES
        fi
    fi
fi

if [ "$executor" = bin/s_compiler ] || [ "$executor" = bin/s ]; then
    # Existing no-gc emit-c path is a historical compiler artifact, not the
    # canonical modular backend_elf64.build authority path.
    if [ "$executor_produces_full_stage1_c" != YES ]; then
        executor_reaches_canonical_parser=NO
        executor_reaches_canonical_semantic=NO
        executor_reaches_canonical_lowering=NO
    fi
fi

bootstrap_cycle=NO
if [ "$executor_requires_stage1" = YES ]; then
    bootstrap_cycle=YES
fi

c_seed_semantic_expansion_required=NO
bootstrap_subset_expansion_required=NO
permanent_dual_authority=NO
if [ "$executor" = NONE ]; then
    c_seed_semantic_expansion_required=UNKNOWN
    bootstrap_subset_expansion_required=UNKNOWN
fi
if [ "$stage1_build_probe" = PASS ]; then
    if strings "$tmp/modular_stage1_build.out" 2>/dev/null | rg -q 'hello from S|bootstrap-subset|artifact-only'; then
        bootstrap_subset_expansion_required=YES
    fi
fi

classification=GENERATED_C_PRODUCER_VIABLE
reason=NONE
if [ "$executor" = s_modular-stage1 ]; then
    classification=NO_NON_CIRCULAR_GENERATED_C_PRODUCER
    reason=emit-c-executor-requires-stage1
elif [ "$executor" = NONE ]; then
    classification=NO_NON_CIRCULAR_GENERATED_C_PRODUCER
    reason=no-executor-can-emit-c-for-canonical-entry
elif [ "$executor_produces_full_stage1_c" != YES ]; then
    classification=NO_NON_CIRCULAR_GENERATED_C_PRODUCER
    reason=emit-c-executor-produces-single-source-or-stub-c-not-full-canonical-stage1
elif [ "$bootstrap_cycle" != NO ]; then
    classification=NO_NON_CIRCULAR_GENERATED_C_PRODUCER
    reason=bootstrap-cycle
elif [ "$c_seed_semantic_expansion_required" = YES ] || [ "$bootstrap_subset_expansion_required" = YES ]; then
    classification=NO_NON_CIRCULAR_GENERATED_C_PRODUCER
    reason=requires-forbidden-root-expansion
fi

common_root=NO
if [ "$classification" = NO_NON_CIRCULAR_GENERATED_C_PRODUCER ]; then
    common_root=BOOTSTRAP_SEMANTIC_EXECUTION_ROOT_MISSING
fi

{
    echo "B6.7.3e2c Generated-C Canonical Stage1 Producer Audit"
    echo "purpose=read-only-audit-no-generated-c-implementation"
    echo "canonical-entry=$entry_rel"
    echo "canonical-closure=$closure"
    echo "canonical-closure-count=$closure_count"
    echo "canonical-closure-contains-entry=$closure_contains_entry"
    echo "canonical-emit-c-capability=$canonical_emit_c_capability"
    echo "emit-c-executor=$executor"
    echo "emit-c-executor-path=$executor_path"
    echo "executor-requires-stage1=$executor_requires_stage1"
    echo "executor-can-consume-37-file-closure=$executor_can_consume_37_file_closure"
    echo "executor-reaches-canonical-parser=$executor_reaches_canonical_parser"
    echo "executor-reaches-canonical-semantic=$executor_reaches_canonical_semantic"
    echo "executor-reaches-canonical-lowering=$executor_reaches_canonical_lowering"
    echo "executor-produces-full-stage1-c=$executor_produces_full_stage1_c"
    echo "executor-output-c-kind=$(classify_output_c "$executor_output_c")"
    echo "host-cc-can-consume-output=$host_cc_can_consume_output"
    echo "bootstrap-cycle=$bootstrap_cycle"
    echo "c-seed-semantic-expansion-required=$c_seed_semantic_expansion_required"
    echo "bootstrap-subset-expansion-required=$bootstrap_subset_expansion_required"
    echo "permanent-dual-authority=$permanent_dual_authority"
    echo "probe-bin-s_compiler=$s_compiler_probe"
    echo "probe-bin-s_compiler-output-kind=$s_compiler_c_kind"
    echo "probe-bin-s=$s_wrapper_probe"
    echo "probe-bin-s-output-kind=$s_wrapper_c_kind"
    echo "probe-s_modular-stage1-emit-c=$stage1_emit_c_probe"
    echo "probe-s_modular-stage1-emit-c-output-kind=$stage1_emit_c_kind"
    echo "probe-s_modular-stage1-build=$stage1_build_probe"
    echo "common-root-if-red=$common_root"
    echo "reason=$reason"
    echo "classification=$classification"
} | tee "$report"

if [ "$classification" != GENERATED_C_PRODUCER_VIABLE ]; then
    exit 1
fi
