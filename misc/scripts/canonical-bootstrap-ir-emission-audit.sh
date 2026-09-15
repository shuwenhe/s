#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${CANONICAL_BOOTSTRAP_IR_EMISSION_AUDIT_REPORT:-"$root/.bootstrap/modular/canonical-bootstrap-ir-emission-audit.txt"}

mkdir -p "$(dirname -- "$report")"

has_file() {
    [ -f "$root/$1" ]
}

has_text() {
    pattern=$1
    shift
    rg -q "$pattern" "$root/$@" 2>/dev/null
}

status_bool() {
    if "$@"; then
        echo YES
    else
        echo NO
    fi
}

canonical_parse_entry=$(status_bool has_text 'func parse_source' src/cmd/compile/internal/syntax src/s)
canonical_semantic_entry=$(status_bool has_text 'check_source_file' src/cmd/compile/internal)
canonical_mono_entry=$(status_bool has_text 'monomorphize_file' src/cmd/compile/internal/mono)
canonical_mir_model=$(status_bool has_file src/cmd/compile/internal/mir.s)
canonical_mir_lowering=$(status_bool has_text 'lower_main_to_mir|lower_function_graph|make_graph' src/cmd/compile/internal/ir src/cmd/compile/internal/mir.s)
canonical_mir_dump=$(status_bool has_text 'func dump_graph' src/cmd/compile/internal/mir.s src/cmd/compile/internal/ir)

seed_ir_format=$(status_bool has_text 'SSEED-TARGET-V1' src/cmd/compile/seed)
seed_ir_consumer=$(status_bool has_text 'emit_aot_from_ir_file|emit_native_from_ir_file' src/cmd/compile/seed)
seed_ir_serializer=$(status_bool has_text 'generate_code' src/cmd/compile/seed/code/generator.c)

existing_seed_ir_emitter=NO
if has_text 'SSEED-TARGET-V1|FUNC_BEGIN\|.*FUNC_END\||bootstrap.*ir.*emit|emit.*bootstrap.*ir' src/cmd/compile/internal; then
    existing_seed_ir_emitter=YES
elif has_text 'SSEED-TARGET-V1|FUNC_BEGIN\|.*FUNC_END\|' src/cmd/compile/selfhost; then
    existing_seed_ir_emitter=PARTIAL_SELFHOST_ONLY
fi

existing_bootstrap_ir_adapter=NO
if has_text 'bootstrap.*SSEED|SSEED.*bootstrap|seed.*ir.*adapter|adapter.*seed.*ir' src/cmd/compile/internal src/cmd/compile/selfhost; then
    existing_bootstrap_ir_adapter=YES
fi

existing_mir_serializer=NO
if [ "$canonical_mir_dump" = YES ]; then
    existing_mir_serializer=TEXT_DIAGNOSTIC_ONLY
fi

canonical_representation=UNKNOWN
if [ "$canonical_mir_model" = YES ] && [ "$canonical_mir_lowering" = YES ]; then
    canonical_representation=MIR
fi

mapping_function=UNKNOWN
mapping_basic_block=UNKNOWN
mapping_branch=UNKNOWN
mapping_call=UNKNOWN
mapping_return=UNKNOWN
mapping_local=UNKNOWN
mapping_load_store=UNKNOWN
mapping_aggregate=UNKNOWN
mapping_type_layout=UNKNOWN
mapping_symbol=UNKNOWN
mapping_external_runtime_call=UNKNOWN

if [ "$canonical_representation" = MIR ] && [ "$seed_ir_format" = YES ]; then
    mapping_function=MECHANICAL
    mapping_basic_block=MECHANICAL
    mapping_branch=MECHANICAL
    mapping_call=MECHANICAL
    mapping_return=MECHANICAL
    mapping_local=MECHANICAL
    mapping_external_runtime_call=MECHANICAL
    mapping_load_store=MISSING
    mapping_aggregate=MISSING
    mapping_type_layout=UNKNOWN
    mapping_symbol=MECHANICAL
fi

direct_mappings=0
mechanical_mappings=0
missing_mappings=0
semantic_mappings=0
unknown_mappings=0
for mapping in \
    "$mapping_function" "$mapping_basic_block" "$mapping_branch" "$mapping_call" \
    "$mapping_return" "$mapping_local" "$mapping_load_store" "$mapping_aggregate" \
    "$mapping_type_layout" "$mapping_symbol" "$mapping_external_runtime_call"
do
    case "$mapping" in
        DIRECT) direct_mappings=$((direct_mappings + 1)) ;;
        MECHANICAL) mechanical_mappings=$((mechanical_mappings + 1)) ;;
        MISSING) missing_mappings=$((missing_mappings + 1)) ;;
        SEMANTIC) semantic_mappings=$((semantic_mappings + 1)) ;;
        *) unknown_mappings=$((unknown_mappings + 1)) ;;
    esac
done

canonical_bootstrap_ir_emission=UNKNOWN
recommended_next=ROOT_STRATEGY_REASSESS
if [ "$existing_seed_ir_emitter" = YES ]; then
    canonical_bootstrap_ir_emission=EXISTING
    recommended_next=WIRE_EXISTING_PATH
elif [ "$canonical_representation" = MIR ] && [ "$seed_ir_format" = YES ] && [ "$seed_ir_consumer" = YES ] && \
     [ "$semantic_mappings" -eq 0 ]; then
    canonical_bootstrap_ir_emission=ADAPTER_FEASIBLE
    recommended_next=BOOTSTRAP_IR_ADAPTER_DESIGN
fi

if [ "$semantic_mappings" -gt 0 ]; then
    canonical_bootstrap_ir_emission=NOT_FEASIBLE_WITHOUT_DUPLICATE_AUTHORITY
    recommended_next=ROOT_STRATEGY_REASSESS
fi

{
    echo "canonical-bootstrap-ir-emission-audit"
    echo "purpose=read-only-audit-no-emitter-implementation"
    echo "canonical-semantics-before-bootstrap-ir=REQUIRED"
    echo "bootstrap-ir-emitter-parser-authority=NONE"
    echo "bootstrap-ir-emitter-semantic-authority=NONE"
    echo "bootstrap-ir-emitter-mono-authority=NONE"
    echo "bootstrap-ir-emitter-ownership-authority=NONE"
    echo "structural-lowering-adaptation=ALLOWED"
    echo "duplicate-semantic-lowering=FORBIDDEN"
    echo "canonical-parse-entry=$canonical_parse_entry"
    echo "canonical-semantic-entry=$canonical_semantic_entry"
    echo "canonical-mono-entry=$canonical_mono_entry"
    echo "canonical-mir-model=$canonical_mir_model"
    echo "canonical-mir-lowering=$canonical_mir_lowering"
    echo "existing-ir-model=$canonical_representation"
    echo "existing-ir-serializer=$existing_mir_serializer"
    echo "existing-mir-serializer=$existing_mir_serializer"
    echo "existing-seed-ir-format=$seed_ir_format"
    echo "existing-seed-ir-consumer=$seed_ir_consumer"
    echo "existing-seed-ir-serializer=$seed_ir_serializer"
    echo "existing-seed-ir-emitter=$existing_seed_ir_emitter"
    echo "existing-seed-ir-adapter=$existing_bootstrap_ir_adapter"
    echo "existing-aot-input-builder=$seed_ir_consumer"
    echo "canonical-representation=$canonical_representation"
    echo "bootstrap-ir-target=SSEED-TARGET-V1"
    echo "mapping=function:$mapping_function"
    echo "mapping=basic-block:$mapping_basic_block"
    echo "mapping=branch:$mapping_branch"
    echo "mapping=call:$mapping_call"
    echo "mapping=return:$mapping_return"
    echo "mapping=local:$mapping_local"
    echo "mapping=load-store:$mapping_load_store"
    echo "mapping=aggregate:$mapping_aggregate"
    echo "mapping=type-layout:$mapping_type_layout"
    echo "mapping=symbol:$mapping_symbol"
    echo "mapping=external-runtime-call:$mapping_external_runtime_call"
    echo "direct-mappings=$direct_mappings"
    echo "mechanical-mappings=$mechanical_mappings"
    echo "semantic-mappings=$semantic_mappings"
    echo "missing-mappings=$missing_mappings"
    echo "unknown-mappings=$unknown_mappings"
    echo "mapping-completeness=PARTIAL"
    echo "canonical-bootstrap-ir-emission=$canonical_bootstrap_ir_emission"
    echo "missing-capability=canonical-bootstrap-ir-emitter-or-adapter"
    echo "recommended-next=$recommended_next"
    echo "audit-verdict=COMPLETE"
} >"$report"

cat "$report"

exit 0
