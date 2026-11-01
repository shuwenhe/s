#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${BOOTSTRAP_IR_ARTIFACT_SCHEMA_REPORT:-"$root/.bootstrap/modular/bootstrap-ir-artifact-schema-design-check.txt"}
modular_dir="$root/.bootstrap/modular"

mkdir -p "$(dirname -- "$report")"

get_field() {
    file=$1
    key=$2
    if [ -f "$file" ]; then
        awk -F= -v key="$key" '$1 == key { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$file"
    else
        echo "UNKNOWN"
    fi
}

format_verdict=$(get_field "$modular_dir/bootstrap-ir-serialization-format-design-check.txt" "verdict")
serializer_authority=$(get_field "$modular_dir/bootstrap-ir-serialization-format-design-check.txt" "serializer-authority")
drop_serializer_semantics=$(get_field "$modular_dir/canonical-drop-authority-completion-audit.txt" "serializer-needs-ownership-analysis")
symbol_sufficient=$(get_field "$modular_dir/canonical-symbol-bootstrap-requirements-audit.txt" "symbol-state-sufficient")

semantic_authority_leak=NO
if [ "$serializer_authority" != REPRESENTATION_ONLY ]; then
    semantic_authority_leak=YES
fi
if [ "$drop_serializer_semantics" = YES ]; then
    semantic_authority_leak=YES
fi

schema_contract_status=NOT_DEFINED
if [ "$format_verdict" = SERIALIZATION_FORMAT_CONTRACT_DEFINED ] && \
   [ "$semantic_authority_leak" = NO ] && \
   [ "$symbol_sufficient" = YES ]; then
    schema_contract_status=DEFINED
fi

{
    echo "bootstrap-ir-artifact-schema-design-check"
    echo "purpose=B5.3-design-only-no-serializer-no-instruction-detail"
    echo "depends-on-format=$format_verdict"
    echo "schema-principle=Schema records decisions"
    echo "schema-principle=Schema does not make decisions"
    echo "artifact-kind=BOOTSTRAP_IR"
    echo "format=SSEED-TARGET-V1"
    echo "format-version=1"
    echo "schema-top-level=header,types,symbols,functions,metadata"
    echo "schema-header=DEFINED"
    echo "header-field=magic:REQUIRED"
    echo "header-field=format-version:REQUIRED"
    echo "header-field=target-arch:REQUIRED"
    echo "header-field=target-os:REQUIRED"
    echo "header-field=target-abi:REQUIRED"
    echo "header-forbidden=generated_at,hostname,username,cwd,absolute_source_path"
    echo "schema-types=DEFINED"
    echo "schema-layout=FINAL_FACTS_ONLY"
    echo "type-field=type-id:STABLE"
    echo "type-field=size:FINAL_FACT"
    echo "type-field=alignment:FINAL_FACT"
    echo "type-field=field-id-or-index:STABLE"
    echo "type-field=field-offset:FINAL_FACT"
    echo "type-field=field-size:FINAL_FACT"
    echo "type-field=field-alignment:FINAL_FACT"
    echo "layout-decision-source=CANONICAL"
    echo "layout-schema-role=RECORD_ONLY"
    echo "serializer-layout-calculation=FORBIDDEN"
    echo "schema-symbols=CANONICAL_IDENTITY"
    echo "symbol-field=stable-id:REQUIRED"
    echo "symbol-field=name:REQUIRED"
    echo "symbol-field=linkage-if-required:OPTIONAL"
    echo "schema-symbol-final-address=FORBIDDEN"
    echo "symbol-final-address=NOT_STORED"
    echo "symbol-machine-address=FORBIDDEN"
    echo "symbol-host-pointer=FORBIDDEN"
    echo "symbol-relocation-authority=CONSUMER"
    echo "symbol-address-assignment-authority=CONSUMER"
    echo "schema-functions=DEFINED"
    echo "function-field=function-id:STABLE"
    echo "function-field=symbol-id:REQUIRED"
    echo "function-field=params:FINAL_ABI_FACTS"
    echo "function-field=return:FINAL_ABI_FACTS"
    echo "function-field=locals-frame:FINAL_FACTS"
    echo "function-field=blocks:REQUIRED"
    echo "function-field=instructions-actions:REQUIRED"
    echo "schema-abi=FINAL_DECISIONS_ONLY"
    echo "abi-decision-source=CANONICAL"
    echo "serializer-abi-decision=FORBIDDEN"
    echo "schema-cfg=REQUIRED"
    echo "schema-instructions=REQUIRED"
    echo "instruction-category=function:REQUIRED"
    echo "instruction-category=basic-block:REQUIRED"
    echo "instruction-category=control-flow-edge:REQUIRED"
    echo "instruction-category=call:REQUIRED"
    echo "instruction-category=return:REQUIRED"
    echo "instruction-category=load-store:REQUIRED"
    echo "instruction-category=aggregate-access:REQUIRED"
    echo "instruction-category=drop-action:REQUIRED"
    echo "instruction-category=symbol-reference:REQUIRED"
    echo "control-flow-order=SEMANTIC"
    echo "instruction-order=SEMANTIC"
    echo "block-identity=STABLE"
    echo "instruction-text-syntax=DEFERRED_TO_SCHEMA_DETAIL"
    echo "schema-drop=FINAL_ACTIONS_ONLY"
    echo "drop-field=action-kind:REQUIRED"
    echo "drop-field=target-value-or-field:REQUIRED"
    echo "drop-field=semantic-order:REQUIRED"
    echo "schema-ownership-analysis-input=FORBIDDEN"
    echo "drop-analysis-input=FORBIDDEN"
    echo "drop-maybe-moved-state=FORBIDDEN"
    echo "drop-borrow-state=FORBIDDEN"
    echo "drop-consumer-rederivation=FORBIDDEN"
    echo "drop-decision-source=CANONICAL"
    echo "serializer-drop-decision=FORBIDDEN"
    echo "metadata-policy=ALLOWLIST_ONLY"
    echo "metadata-allowed=semantic-identity,target-identity,format-compatibility,reproducible-canonical-state"
    echo "metadata-default=FORBIDDEN_UNTIL_JUSTIFIED"
    echo "schema-decision-authority=NONE"
    echo "schema-role=RECORD_FINALIZED_CANONICAL_STATE"
    echo "serializer-parser-authority=NONE"
    echo "serializer-semantic-authority=NONE"
    echo "serializer-type-authority=NONE"
    echo "serializer-mono-authority=NONE"
    echo "serializer-ownership-authority=NONE"
    echo "serializer-drop-authority=NONE"
    echo "serializer-layout-authority=NONE"
    echo "serializer-abi-authority=NONE"
    echo "serializer-symbol-resolution-authority=NONE"
    echo "mechanical-copy-check=REQUIRED"
    echo "semantic-authority-leak=$semantic_authority_leak"
    echo "non-goal=write-serializer"
    echo "non-goal=generate-bootstrap-ir"
    echo "non-goal=define-every-instruction-field"
    echo "non-goal=implement-equivalence-check"
    echo "next=B5.4-equivalence-regeneration-contract"
    echo "schema-contract-status=$schema_contract_status"
    if [ "$schema_contract_status" = DEFINED ]; then
        echo "verdict=BOOTSTRAP_IR_ARTIFACT_SCHEMA_DEFINED"
    else
        echo "verdict=BOOTSTRAP_IR_ARTIFACT_SCHEMA_BLOCKED"
    fi
} >"$report"

cat "$report"

if [ "$schema_contract_status" = DEFINED ]; then
    exit 0
fi

exit 1
