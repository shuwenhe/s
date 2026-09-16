#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
entry_rel="src/cmd/compile/modular_build_main.s"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
seed="${SEED_COMPILER_BIN:-"$root/bin/s_seed"}"

bootstrap_ir="${CANONICAL_STAGE1_BOOTSTRAP_IR:-"$root/src/cmd/compile/bootstrap/bootstrap.ir"}"
manifest="${CANONICAL_STAGE1_BOOTSTRAP_MANIFEST:-"$root/src/cmd/compile/bootstrap/bootstrap.manifest"}"
generator="${CANONICAL_STAGE1_BOOTSTRAP_IR_GENERATOR:-"$root/src/cmd/compile/bootstrap/generate_bootstrap_ir.sh"}"
legacy_ir="$root/src/cmd/compile/seed/stage1.ir"
stage1_out="${CANONICAL_STAGE1_PRODUCER_OUT:-"$root/.bootstrap/modular/s_modular-stage1-from-bootstrap-ir"}"
report="${CANONICAL_STAGE1_PRODUCER_REPORT:-"$root/.bootstrap/modular/b6.7.3e3-canonical-stage1-bootstrap-ir-producer.txt"}"

tmp="${TMPDIR:-/tmp}/b6.7.3e3-stage1-producer.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$(dirname "$report")"

sha_file() {
    if [ -f "$1" ]; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "NONE"
    fi
}

manifest_field() {
    local key="$1"
    if [ -f "$manifest" ]; then
        awk -F= -v key="$key" '$1 == key { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$manifest"
    else
        echo "NONE"
    fi
}

closure_count=0
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
fi

canonical_snapshot_hash=NONE
if [ -f "$closure" ]; then
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if [ -f "$root/$rel" ]; then
            shasum -a 256 "$root/$rel" | awk -v rel="$rel" '{ print $1 "  " rel }'
        else
            printf 'MISSING  %s\n' "$rel"
        fi
    done <"$closure" >"$tmp/closure.hashes"
    canonical_snapshot_hash=$(shasum -a 256 "$tmp/closure.hashes" | awk '{print $1}')
fi

bootstrap_ir_present=NO
[ -f "$bootstrap_ir" ] && bootstrap_ir_present=YES

bootstrap_ir_header=NO
if [ -f "$bootstrap_ir" ] && head -n 1 "$bootstrap_ir" | grep -qx 'SSEED-TARGET-V1'; then
    bootstrap_ir_header=YES
fi

bootstrap_ir_hash=$(sha_file "$bootstrap_ir")
legacy_ir_hash=$(sha_file "$legacy_ir")
manifest_present=NO
[ -f "$manifest" ] && manifest_present=YES

manifest_closure_count=$(manifest_field canonical-closure-count)
manifest_snapshot_hash=$(manifest_field canonical-snapshot-hash)
manifest_ir_hash=$(manifest_field bootstrap-ir-hash)
manifest_regeneration_command=$(manifest_field regeneration-command)

generator_present=NO
generator_executable=NO
generator_consumes_canonical_closure=NO
generator_outputs_bootstrap_ir=NO
generator_uses_stage1_to_produce_bootstrap_ir=NO
generator_expands_c_seed_semantic=NO
generator_modifies_bootstrap_subset=NO
generator_non_circular=NO
if [ -f "$generator" ]; then
    generator_present=YES
    [ -x "$generator" ] && generator_executable=YES
    if rg -q 'canonical-closure|STAGE0_CLOSURE|modular_build_main\.s|source_closure' "$generator"; then
        generator_consumes_canonical_closure=YES
    fi
    if rg -q 'bootstrap\.ir|CANONICAL_STAGE1_REGENERATED_IR|CANONICAL_STAGE1_BOOTSTRAP_IR' "$generator"; then
        generator_outputs_bootstrap_ir=YES
    fi
    if rg -q 's_modular-stage1|stage1.*bootstrap\.ir|bootstrap\.ir.*stage1' "$generator"; then
        generator_uses_stage1_to_produce_bootstrap_ir=YES
    fi
    if rg -q 'seed/semantic/analyzer\.c|seed_compile_source_text|semantic_analyze' "$generator"; then
        generator_expands_c_seed_semantic=YES
    fi
    if rg -q 'bootstrap_subset|src/cmd/compile/stage0/bootstrap_subset\.c' "$generator"; then
        generator_modifies_bootstrap_subset=YES
    fi
fi
if [ "$generator_present" = YES ] && \
   [ "$generator_executable" = YES ] && \
   [ "$generator_consumes_canonical_closure" = YES ] && \
   [ "$generator_outputs_bootstrap_ir" = YES ] && \
   [ "$generator_uses_stage1_to_produce_bootstrap_ir" = NO ] && \
   [ "$generator_expands_c_seed_semantic" = NO ] && \
   [ "$generator_modifies_bootstrap_subset" = NO ]; then
    generator_non_circular=YES
fi

bootstrap_ir_source=UNKNOWN
provenance_integrity=NO
if [ "$manifest_present" = YES ] && \
   [ "$manifest_closure_count" = "$closure_count" ] && \
   [ "$manifest_snapshot_hash" = "$canonical_snapshot_hash" ] && \
   [ "$manifest_ir_hash" = "$bootstrap_ir_hash" ] && \
   [ "$manifest_regeneration_command" != UNKNOWN ] && \
   [ "$manifest_regeneration_command" != NONE ]; then
    bootstrap_ir_source=canonical-snapshot
    provenance_integrity=YES
fi

bootstrap_ir_consumer=UNKNOWN
stage1_artifact_produced=NO
stage1_artifact_executable=NO
stage1_entry_contained=NO
canonical_build_runtime_contained=NO
backend_elf64_build_contained=NO
bootstrap_subset_used_for_stage1_production=UNKNOWN

emit_status=NOT_RUN
if [ "$bootstrap_ir_present" = YES ] && [ "$bootstrap_ir_header" = YES ] && [ -x "$seed" ]; then
    rm -f "$stage1_out"
    set +e
    S_SOURCE_ROOT="$root" "$seed" --emit-aot "$bootstrap_ir" "$stage1_out" >"$tmp/emit-aot.log" 2>&1
    emit_status=$?
    set -e
    bootstrap_ir_consumer=existing-seed-ir/aot-consumer
    [ -f "$stage1_out" ] && stage1_artifact_produced=YES
    [ -x "$stage1_out" ] && stage1_artifact_executable=YES
fi

if [ "$stage1_artifact_executable" = YES ]; then
    strings "$stage1_out" >"$tmp/stage1.strings" 2>/dev/null || true
    nm "$stage1_out" >"$tmp/stage1.symbols" 2>/dev/null || true
    if grep -Eq 'modular_build_main|canonical_stage1_main|stage1_entry|FUNC_BEGIN\|main' "$tmp/stage1.strings" "$tmp/stage1.symbols"; then
        stage1_entry_contained=YES
    fi
    if grep -Eq 'modular_build_main|compile\.internal\.backend_elf64\.build|canonical_build' "$tmp/stage1.strings" "$tmp/stage1.symbols"; then
        canonical_build_runtime_contained=YES
    fi
    if grep -Eq 'backend_elf64|compile_internal_backend_elf64|compile\.internal\.backend_elf64' "$tmp/stage1.strings" "$tmp/stage1.symbols"; then
        backend_elf64_build_contained=YES
    fi
    bootstrap_subset_used_for_stage1_production=NO
    if grep -Eq 'bootstrap_subset|bootstrap-subset' "$tmp/stage1.strings" "$tmp/stage1.symbols"; then
        bootstrap_subset_used_for_stage1_production=YES
    fi
fi

c_seed_semantic_expanded=NO
if ! git -C "$root" diff --quiet -- src/cmd/compile/seed/semantic/analyzer.c 2>/dev/null; then
    c_seed_semantic_expanded=YES
fi

canonical_resolver_modified=NO
if ! git -C "$root" diff --quiet -- src/cmd/compile/internal/semantic.s 2>/dev/null; then
    canonical_resolver_modified=YES
fi

bootstrap_cycle=NO

regenerated_ir="${CANONICAL_STAGE1_REGENERATED_IR:-"$tmp/bootstrap.regenerated.ir"}"
regeneration_attempted=NO
regeneration_status=NOT_RUN
regeneration_equivalence=NOT_PROVEN
equivalence_level=NONE
if [ "$manifest_regeneration_command" != UNKNOWN ] && [ "$manifest_regeneration_command" != NONE ]; then
    regeneration_attempted=YES
    set +e
    (cd "$root" && CANONICAL_STAGE1_REGENERATED_IR="$regenerated_ir" sh -c "$manifest_regeneration_command") >"$tmp/regenerate.log" 2>&1
    regeneration_status=$?
    set -e
    if [ "$regeneration_status" -eq 0 ] && [ -f "$regenerated_ir" ]; then
        if cmp -s "$bootstrap_ir" "$regenerated_ir"; then
            regeneration_equivalence=YES
            equivalence_level=BYTE_FOR_BYTE
        else
            regeneration_equivalence=NO
            equivalence_level=DIFFERS
        fi
    fi
fi

legacy_ir_classification=NOT_APPLICABLE
if [ "$bootstrap_ir_present" != YES ] && [ -f "$legacy_ir" ]; then
    if rg -q '^FUNC_BEGIN\|main\|_|_' "$legacy_ir" && \
       rg -q 'CALL\|.*\|build_main\|1' "$legacy_ir" && \
       ! rg -q 'modular_build_main|backend_elf64|semantic\.check_source_file|parse_source' "$legacy_ir"; then
        legacy_ir_classification=LEGACY_BOOTSTRAP_SUBSET_IR_NOT_CANONICAL_STAGE1
    fi
fi

classification=B6.7.3e3_GREEN
missing_capability=NONE
if [ "$bootstrap_ir_present" != YES ]; then
    if [ "$generator_non_circular" = YES ]; then
        classification=BOOTSTRAP_IR_ARTIFACT_MISSING
        missing_capability=checked-in-canonical-bootstrap-ir
    else
        classification=BOOTSTRAP_IR_GENERATOR_MISSING
        missing_capability=canonical-snapshot-to-bootstrap-ir-generator
    fi
elif [ "$bootstrap_ir_header" != YES ]; then
    classification=BOOTSTRAP_IR_FORMAT_GAP
    missing_capability=SSEED-TARGET-V1-header
elif [ "$provenance_integrity" != YES ]; then
    classification=BOOTSTRAP_IR_PROVENANCE_GAP
    missing_capability=bootstrap-ir-source-manifest
elif [ "$emit_status" != 0 ]; then
    classification=BOOTSTRAP_IR_CONSUMER_GAP
    missing_capability=existing-seed-ir-aot-consumption
elif [ "$stage1_artifact_produced" != YES ] || [ "$stage1_artifact_executable" != YES ]; then
    classification=STAGE1_ARTIFACT_PRODUCTION_GAP
    missing_capability=stage1-native-artifact
elif [ "$stage1_entry_contained" != YES ] || \
     [ "$canonical_build_runtime_contained" != YES ] || \
     [ "$backend_elf64_build_contained" != YES ]; then
    classification=RUNTIME_CONTENT_GAP
    missing_capability=canonical-stage1-runtime-content
elif [ "$bootstrap_subset_used_for_stage1_production" != NO ]; then
    classification=BOOTSTRAP_SUBSET_AUTHORITY_LEAK
    missing_capability=remove-bootstrap-subset-from-stage1-producer
elif [ "$c_seed_semantic_expanded" != NO ]; then
    classification=AUTHORITY_BOUNDARY_VIOLATION
    missing_capability=c-seed-semantic-must-not-expand
elif [ "$canonical_resolver_modified" != NO ]; then
    classification=OUT_OF_SCOPE_CANONICAL_RESOLVER_CHANGE
    missing_capability=canonical-resolver-frozen-for-e3
elif [ "$regeneration_equivalence" != YES ]; then
    classification=REGENERATION_EQUIVALENCE_GAP
    missing_capability=bootstrap-ir-regeneration-equivalence
fi

{
    echo "B6.7.3e3 Canonical Stage1 Bootstrap-IR Producer"
    echo "bootstrap-ir=$bootstrap_ir"
    echo "bootstrap-ir-present=$bootstrap_ir_present"
    echo "bootstrap-ir-format=SSEED-TARGET-V1"
    echo "bootstrap-ir-header=$bootstrap_ir_header"
    echo "bootstrap-ir-source=$bootstrap_ir_source"
    echo "bootstrap-ir-consumer=$bootstrap_ir_consumer"
    echo "stage1-output=$stage1_out"
    echo "stage1-artifact-produced=$stage1_artifact_produced"
    echo "stage1-artifact-executable=$stage1_artifact_executable"
    echo "stage1-entry-contained=$stage1_entry_contained"
    echo "canonical-build-runtime-contained=$canonical_build_runtime_contained"
    echo "backend-elf64-build-contained=$backend_elf64_build_contained"
    echo "bootstrap-subset-used-for-stage1-production=$bootstrap_subset_used_for_stage1_production"
    echo "c-seed-semantic-expanded=$c_seed_semantic_expanded"
    echo "canonical-resolver-modified=$canonical_resolver_modified"
    echo "bootstrap-cycle=$bootstrap_cycle"
    echo "bootstrap-ir-source-manifest=$manifest"
    echo "bootstrap-ir-source-manifest-present=$manifest_present"
    echo "bootstrap-ir-generator=$generator"
    echo "bootstrap-ir-generator-present=$generator_present"
    echo "bootstrap-ir-generator-executable=$generator_executable"
    echo "bootstrap-ir-generator-consumes-canonical-closure=$generator_consumes_canonical_closure"
    echo "bootstrap-ir-generator-outputs-bootstrap-ir=$generator_outputs_bootstrap_ir"
    echo "bootstrap-ir-generator-uses-stage1-to-produce-bootstrap-ir=$generator_uses_stage1_to_produce_bootstrap_ir"
    echo "bootstrap-ir-generator-expands-c-seed-semantic=$generator_expands_c_seed_semantic"
    echo "bootstrap-ir-generator-modifies-bootstrap-subset=$generator_modifies_bootstrap_subset"
    echo "bootstrap-ir-generator-non-circular=$generator_non_circular"
    echo "canonical-closure=$closure"
    echo "canonical-closure-count=$closure_count"
    echo "canonical-snapshot-hash=$canonical_snapshot_hash"
    echo "bootstrap-ir-hash=$bootstrap_ir_hash"
    echo "manifest-canonical-closure-count=$manifest_closure_count"
    echo "manifest-canonical-snapshot-hash=$manifest_snapshot_hash"
    echo "manifest-bootstrap-ir-hash=$manifest_ir_hash"
    echo "regeneration-command=$manifest_regeneration_command"
    echo "regeneration-attempted=$regeneration_attempted"
    echo "regeneration-status=$regeneration_status"
    echo "regeneration-equivalence=$regeneration_equivalence"
    echo "equivalence-level=$equivalence_level"
    echo "legacy-ir=$legacy_ir"
    echo "legacy-ir-hash=$legacy_ir_hash"
    echo "legacy-ir-classification=$legacy_ir_classification"
    echo "missing-capability=$missing_capability"
    echo "classification=$classification"
} | tee "$report"

if [ "$classification" != B6.7.3e3_GREEN ]; then
    exit 1
fi
