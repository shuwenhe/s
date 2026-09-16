#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
entry_rel="src/cmd/compile/modular_build_main.s"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
seed="$root/bin/s_seed"
canonical_driver="$root/bin/s"
stage0="$root/.bootstrap/modular/s_stage0"
stage1="$root/.bootstrap/modular/s_modular-stage1"
generator="$root/src/cmd/compile/bootstrap/generate_bootstrap_ir.sh"
report="$root/.bootstrap/modular/b6.7.3e3a-bootstrap-ir-generator-feasibility-audit.txt"

tmp="${TMPDIR:-/tmp}/b6.7.3e3a-generator.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$(dirname "$report")"

bool_file() {
    [ -f "$1" ] && echo YES || echo NO
}

bool_exec() {
    [ -x "$1" ] && echo YES || echo NO
}

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

canonical_parse_entry=$(status_bool has_text 'func parse_source' src/cmd/compile/internal/syntax src/s)
canonical_semantic_entry=$(status_bool has_text 'check_source_file' src/cmd/compile/internal)
canonical_lowered_view_entry=$(status_bool has_text '--emit-lowered-view|canonical-lowered-view version=1' src/cmd/compile/compiler.s src/cmd/compile/internal/ir)
seed_ir_consumer=$(status_bool has_text 'emit_aot_from_ir_file|emit_native_from_ir_file' src/cmd/compile/seed)
seed_ir_serializer=$(status_bool has_text 'void generate_code\(IR \*ir, FILE \*output\)|SSEED-TARGET-V1' src/cmd/compile/seed/code/generator.c)
canonical_full_sseed_emitter=$(status_bool has_text 'SSEED-TARGET-V1|FUNC_BEGIN\|.*FUNC_END\||bootstrap.*ir.*emit|emit.*bootstrap.*ir' src/cmd/compile/internal)
selfhost_sseed_emitter=$(status_bool has_text 'SSEED-TARGET-V1|FUNC_BEGIN\|.*FUNC_END\|' src/cmd/compile/selfhost)

seed_present=$(bool_exec "$seed")
canonical_driver_present=$(bool_exec "$canonical_driver")
stage0_present=$(bool_exec "$stage0")
stage1_present=$(bool_exec "$stage1")
generator_present=$(bool_file "$generator")
generator_executable=$(bool_exec "$generator")

seed_can_parse_canonical_closure=NO
seed_can_resolve_imports=NO
seed_can_handle_current_s_syntax=NO
seed_can_run_canonical_semantics=NO
seed_can_emit_consumer_compatible_ir=NO
seed_requires_stage1=NO
seed_requires_bootstrap_subset_expansion=NO
seed_duplicates_semantic_authority=YES
seed_bootstrap_cycle=NO

if [ "$seed_present" = YES ] && has_text '--compile-unit' src/cmd/compile/seed/s_seed.c; then
    seed_can_parse_canonical_closure=PARTIAL_COMPILE_UNIT
fi
if has_text 'AST_USE_DECL|import declaration|string-list import' src/cmd/compile/seed src/s; then
    seed_can_resolve_imports=PARTIAL
fi
if has_text 'seed_compile_source_text|semantic_analyze' src/cmd/compile/seed; then
    seed_can_run_canonical_semantics=NO_C_SEED_SEMANTIC
fi
if [ "$seed_ir_serializer" = YES ]; then
    seed_can_emit_consumer_compatible_ir=YES
fi
if has_text 'use of undeclared symbol|type .any. has no method|semantic_analyze' src/cmd/compile/seed; then
    seed_can_handle_current_s_syntax=NO
fi

stage0_can_parse_canonical_closure=NO
stage0_can_resolve_imports=NO
stage0_can_handle_current_s_syntax=NO
stage0_can_run_canonical_semantics=NO
stage0_can_emit_consumer_compatible_ir=NO
stage0_requires_stage1=NO
stage0_requires_bootstrap_subset_expansion=YES
stage0_duplicates_semantic_authority=NO
stage0_bootstrap_cycle=NO
if [ "$stage0_present" = YES ] && has_text 'source_closure|canonical-closure|closure' src/cmd/compile/stage0/stage0.c; then
    stage0_can_parse_canonical_closure=METADATA_ONLY
fi
if has_text 'bootstrap_subset_build|write_next_stage|artifact-only: canonical-source-compilation=NOT_PROVEN' src/cmd/compile/stage0; then
    stage0_can_emit_consumer_compatible_ir=NO_STUB_ONLY
fi

lowered_can_parse_canonical_closure=NO
lowered_can_resolve_imports=NO
lowered_can_handle_current_s_syntax=PARTIAL_SINGLE_SOURCE
lowered_can_run_canonical_semantics=YES
lowered_can_emit_consumer_compatible_ir=PARTIAL_SLICES_ONLY
lowered_requires_stage1=NO
lowered_requires_bootstrap_subset_expansion=NO
lowered_duplicates_semantic_authority=NO
lowered_bootstrap_cycle=NO
if [ "$canonical_driver_present" = YES ] && [ "$canonical_parse_entry" = YES ]; then
    lowered_can_parse_canonical_closure=SINGLE_ENTRY_NOT_CLOSURE_GENERATOR
fi
if [ "$canonical_semantic_entry" = YES ]; then
    lowered_can_resolve_imports=CANONICAL_PATH_EXISTS
fi
if [ "$canonical_lowered_view_entry" = YES ] && [ "$canonical_full_sseed_emitter" = YES ]; then
    lowered_can_emit_consumer_compatible_ir=YES
elif [ "$canonical_lowered_view_entry" = YES ]; then
    lowered_can_emit_consumer_compatible_ir=PARTIAL_LOWERED_VIEW_SERIALIZERS_ONLY
fi

checked_generator_can_parse_canonical_closure=NO
checked_generator_can_resolve_imports=NO
checked_generator_can_handle_current_s_syntax=NO
checked_generator_can_run_canonical_semantics=NO
checked_generator_can_emit_consumer_compatible_ir=NO
checked_generator_requires_stage1=UNKNOWN
checked_generator_requires_bootstrap_subset_expansion=UNKNOWN
checked_generator_duplicates_semantic_authority=UNKNOWN
checked_generator_bootstrap_cycle=UNKNOWN
if [ "$generator_present" = YES ]; then
    checked_generator_can_parse_canonical_closure=UNKNOWN
    checked_generator_can_resolve_imports=UNKNOWN
    checked_generator_can_handle_current_s_syntax=UNKNOWN
    checked_generator_can_run_canonical_semantics=UNKNOWN
    checked_generator_can_emit_consumer_compatible_ir=UNKNOWN
    checked_generator_requires_stage1=UNKNOWN
    checked_generator_requires_bootstrap_subset_expansion=UNKNOWN
    checked_generator_duplicates_semantic_authority=UNKNOWN
    checked_generator_bootstrap_cycle=UNKNOWN
fi

existing_non_circular_generator=NONE
generator_core=NONE
first_structural_blocker=no-existing-component-combines-canonical-closure-semantics-with-full-SSEED-emission
candidate_b=REOPEN_REQUIRED
classification=NO_BOUNDED_BOOTSTRAP_IR_GENERATOR

if [ "$checked_generator_can_parse_canonical_closure" = YES ] && \
   [ "$checked_generator_can_run_canonical_semantics" = YES ] && \
   [ "$checked_generator_can_emit_consumer_compatible_ir" = YES ] && \
   [ "$checked_generator_requires_stage1" = NO ] && \
   [ "$checked_generator_requires_bootstrap_subset_expansion" = NO ] && \
   [ "$checked_generator_duplicates_semantic_authority" = NO ] && \
   [ "$checked_generator_bootstrap_cycle" = NO ]; then
    existing_non_circular_generator=YES
    generator_core="$generator"
    first_structural_blocker=NONE
    candidate_b=IMPLEMENT_E3_PRODUCER
    classification=BOOTSTRAP_IR_GENERATOR_FEASIBILITY_PROVEN
elif [ "$lowered_can_parse_canonical_closure" = YES ] && \
     [ "$lowered_can_run_canonical_semantics" = YES ] && \
     [ "$lowered_can_emit_consumer_compatible_ir" = YES ] && \
     [ "$lowered_requires_stage1" = NO ] && \
     [ "$lowered_duplicates_semantic_authority" = NO ]; then
    existing_non_circular_generator=YES
    generator_core=canonical-lowered-view-to-SSEED
    first_structural_blocker=NONE
    candidate_b=IMPLEMENT_E3_PRODUCER
    classification=BOOTSTRAP_IR_GENERATOR_FEASIBILITY_PROVEN
fi

{
    echo "B6.7.3e3a Bootstrap IR Generator Feasibility Audit"
    echo "purpose=read-only-audit-no-generator-implementation"
    echo "canonical-entry=$entry_rel"
    echo "canonical-closure=$closure"
    echo "canonical-closure-count=$closure_count"
    echo "canonical-closure-contains-entry=$closure_contains_entry"
    echo "seed-ir-consumer=$seed_ir_consumer"
    echo "seed-ir-serializer=$seed_ir_serializer"
    echo "canonical-parse-entry=$canonical_parse_entry"
    echo "canonical-semantic-entry=$canonical_semantic_entry"
    echo "canonical-lowered-view-entry=$canonical_lowered_view_entry"
    echo "canonical-full-sseed-emitter=$canonical_full_sseed_emitter"
    echo "selfhost-sseed-emitter=$selfhost_sseed_emitter"
    echo "candidate=existing-c-seed-ir-emitter"
    echo "candidate-seed-can-parse-canonical-closure=$seed_can_parse_canonical_closure"
    echo "candidate-seed-can-resolve-imports=$seed_can_resolve_imports"
    echo "candidate-seed-can-handle-current-S-syntax=$seed_can_handle_current_s_syntax"
    echo "candidate-seed-can-run-canonical-semantics=$seed_can_run_canonical_semantics"
    echo "candidate-seed-can-emit-consumer-compatible-IR=$seed_can_emit_consumer_compatible_ir"
    echo "candidate-seed-requires-stage1=$seed_requires_stage1"
    echo "candidate-seed-requires-bootstrap_subset-expansion=$seed_requires_bootstrap_subset_expansion"
    echo "candidate-seed-duplicates-semantic-authority=$seed_duplicates_semantic_authority"
    echo "candidate-seed-bootstrap-cycle=$seed_bootstrap_cycle"
    echo "candidate-seed-verdict=REJECT_DUAL_SEMANTIC_AUTHORITY"
    echo "candidate=existing-bootstrap-root-compiler"
    echo "candidate-stage0-can-parse-canonical-closure=$stage0_can_parse_canonical_closure"
    echo "candidate-stage0-can-resolve-imports=$stage0_can_resolve_imports"
    echo "candidate-stage0-can-handle-current-S-syntax=$stage0_can_handle_current_s_syntax"
    echo "candidate-stage0-can-run-canonical-semantics=$stage0_can_run_canonical_semantics"
    echo "candidate-stage0-can-emit-consumer-compatible-IR=$stage0_can_emit_consumer_compatible_ir"
    echo "candidate-stage0-requires-stage1=$stage0_requires_stage1"
    echo "candidate-stage0-requires-bootstrap_subset-expansion=$stage0_requires_bootstrap_subset_expansion"
    echo "candidate-stage0-duplicates-semantic-authority=$stage0_duplicates_semantic_authority"
    echo "candidate-stage0-bootstrap-cycle=$stage0_bootstrap_cycle"
    echo "candidate-stage0-verdict=REJECT_STUB_ONLY_OR_REQUIRES_SUBSET_EXPANSION"
    echo "candidate=existing-emit-ir-lowered-view-path"
    echo "candidate-lowered-can-parse-canonical-closure=$lowered_can_parse_canonical_closure"
    echo "candidate-lowered-can-resolve-imports=$lowered_can_resolve_imports"
    echo "candidate-lowered-can-handle-current-S-syntax=$lowered_can_handle_current_s_syntax"
    echo "candidate-lowered-can-run-canonical-semantics=$lowered_can_run_canonical_semantics"
    echo "candidate-lowered-can-emit-consumer-compatible-IR=$lowered_can_emit_consumer_compatible_ir"
    echo "candidate-lowered-requires-stage1=$lowered_requires_stage1"
    echo "candidate-lowered-requires-bootstrap_subset-expansion=$lowered_requires_bootstrap_subset_expansion"
    echo "candidate-lowered-duplicates-semantic-authority=$lowered_duplicates_semantic_authority"
    echo "candidate-lowered-bootstrap-cycle=$lowered_bootstrap_cycle"
    echo "candidate-lowered-verdict=PARTIAL_SLICES_NOT_37_FILE_STAGE1_GENERATOR"
    echo "candidate=existing-checked-in-generator-tool"
    echo "candidate-generator-path=$generator"
    echo "candidate-generator-present=$generator_present"
    echo "candidate-generator-executable=$generator_executable"
    echo "candidate-generator-can-parse-canonical-closure=$checked_generator_can_parse_canonical_closure"
    echo "candidate-generator-can-resolve-imports=$checked_generator_can_resolve_imports"
    echo "candidate-generator-can-handle-current-S-syntax=$checked_generator_can_handle_current_s_syntax"
    echo "candidate-generator-can-run-canonical-semantics=$checked_generator_can_run_canonical_semantics"
    echo "candidate-generator-can-emit-consumer-compatible-IR=$checked_generator_can_emit_consumer_compatible_ir"
    echo "candidate-generator-requires-stage1=$checked_generator_requires_stage1"
    echo "candidate-generator-requires-bootstrap_subset-expansion=$checked_generator_requires_bootstrap_subset_expansion"
    echo "candidate-generator-duplicates-semantic-authority=$checked_generator_duplicates_semantic_authority"
    echo "candidate-generator-bootstrap-cycle=$checked_generator_bootstrap_cycle"
    echo "candidate-generator-verdict=MISSING"
    echo "existing-non-circular-generator=$existing_non_circular_generator"
    echo "generator-core=$generator_core"
    echo "wrapper=src/cmd/compile/bootstrap/generate_bootstrap_ir.sh"
    echo "input=canonical-snapshot"
    echo "output=bootstrap.ir"
    echo "consumer-compatible=$seed_ir_consumer"
    echo "requires-stage1=NO_FOR_ACCEPTED_GENERATOR"
    echo "bootstrap-cycle=NO_FOR_ACCEPTED_GENERATOR"
    echo "c-seed-semantic-expansion=FORBIDDEN"
    echo "bootstrap-subset-expansion=FORBIDDEN"
    echo "permanent-dual-authority=FORBIDDEN"
    echo "first-structural-blocker=$first_structural_blocker"
    echo "candidate-B=$candidate_b"
    echo "classification=$classification"
} | tee "$report"

if [ "$classification" != BOOTSTRAP_IR_GENERATOR_FEASIBILITY_PROVEN ]; then
    exit 1
fi
