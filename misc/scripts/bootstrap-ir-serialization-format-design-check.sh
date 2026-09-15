#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${BOOTSTRAP_IR_SERIALIZATION_FORMAT_REPORT:-"$root/.bootstrap/modular/bootstrap-ir-serialization-format-design-check.txt"}
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

boundary_verdict=$(get_field "$modular_dir/bootstrap-ir-snapshot-boundary-design-check.txt" "verdict")
snapshot_input=$(get_field "$modular_dir/bootstrap-ir-snapshot-boundary-design-check.txt" "snapshot-input")
serializer_authority=$(get_field "$modular_dir/bootstrap-ir-snapshot-boundary-design-check.txt" "serializer-authority")

format_contract_status=NOT_DEFINED
if [ "$boundary_verdict" = SNAPSHOT_BOUNDARY_CONTRACT_DEFINED ] && \
   [ "$snapshot_input" = CANONICAL_LOWERED_STATE ] && \
   [ "$serializer_authority" = REPRESENTATION_ONLY ]; then
    format_contract_status=DEFINED
fi

{
    echo "bootstrap-ir-serialization-format-design-check"
    echo "purpose=B5.2-design-only-no-schema-no-serializer"
    echo "depends-on-boundary=$boundary_verdict"
    echo "artifact-kind=BOOTSTRAP_IR"
    echo "format=SSEED-TARGET-V1"
    echo "format-version=1"
    echo "format-version-location=ARTIFACT_HEADER"
    echo "encoding=UTF-8"
    echo "line-ending=LF"
    echo "serialization-determinism=REQUIRED"
    echo "canonical-ordering=REQUIRED"
    echo "semantic-order-preservation=REQUIRED"
    echo "unordered-set-map-order=CANONICAL_SORT"
    echo "incidental-memory-order=FORBIDDEN"
    echo "function-order=DETERMINISTIC_CANONICAL_KEY"
    echo "block-order=SEMANTIC_CFG_ORDER_PRESERVED"
    echo "instruction-order=SEMANTIC_ORDER_PRESERVED"
    echo "drop-action-order=SEMANTIC_ORDER_PRESERVED"
    echo "symbol-order=DETERMINISTIC_CANONICAL_KEY"
    echo "type-order=DETERMINISTIC_CANONICAL_KEY"
    echo "local-order=DETERMINISTIC_CANONICAL_KEY_OR_SEMANTIC_SLOT_ORDER"
    echo "metadata-order=DETERMINISTIC_CANONICAL_KEY"
    echo "whitespace=NORMALIZED"
    echo "indentation=FIXED"
    echo "integer-format=CANONICAL_DECIMAL"
    echo "boolean-format=FIXED"
    echo "string-escaping=CANONICAL"
    echo "newline=LF"
    echo "trailing-whitespace=FORBIDDEN"
    echo "final-newline=REQUIRED"
    echo "float-format=DEFERRED_UNTIL_FLOAT_BOOTSTRAP_IR"
    echo "timestamps=FORBIDDEN"
    echo "absolute-paths=FORBIDDEN"
    echo "absolute-source-paths=FORBIDDEN"
    echo "temporary-paths=FORBIDDEN"
    echo "random-ids=FORBIDDEN"
    echo "process-ids=FORBIDDEN"
    echo "thread-ids=FORBIDDEN"
    echo "pointer-addresses=FORBIDDEN"
    echo "memory-addresses=FORBIDDEN"
    echo "hash-iteration-order=FORBIDDEN"
    echo "host-dependent-order=FORBIDDEN"
    echo "hostname=FORBIDDEN"
    echo "username=FORBIDDEN"
    echo "working-directory=FORBIDDEN"
    echo "build-session-id=FORBIDDEN"
    echo "host-os-specific-state=FORBIDDEN"
    echo "host-architecture-specific-state=FORBIDDEN"
    echo "host-endianness-leak=FORBIDDEN"
    echo "host-pointer-width-leak=FORBIDDEN"
    echo "target-specific-state=ALLOWED_IF_EXPLICIT"
    echo "target-os-state=ALLOWED_IF_TARGET_SEMANTIC"
    echo "target-architecture-state=ALLOWED_IF_TARGET_SEMANTIC"
    echo "stable-identities=REQUIRED"
    echo "symbol-id=STABLE_AND_REPRODUCIBLE"
    echo "function-id=STABLE_AND_REPRODUCIBLE"
    echo "block-id=STABLE_AND_REPRODUCIBLE"
    echo "type-id=STABLE_AND_REPRODUCIBLE"
    echo "local-id=STABLE_AND_REPRODUCIBLE"
    echo "identity-source=CANONICAL_IDENTITY_NOT_POINTER_OR_HASH_BUCKET"
    echo "identity-algorithm=DEFERRED_TO_SCHEMA_CONTRACT"
    echo "serializer-parser-authority=NONE"
    echo "serializer-semantic-authority=NONE"
    echo "serializer-type-authority=NONE"
    echo "serializer-mono-authority=NONE"
    echo "serializer-ownership-authority=NONE"
    echo "serializer-drop-authority=NONE"
    echo "serializer-layout-authority=NONE"
    echo "serializer-abi-authority=NONE"
    echo "serializer-symbol-resolution-authority=NONE"
    echo "serializer-authority=REPRESENTATION_ONLY"
    echo "allowed-operation=READ_FINALIZED_CANONICAL_STATE"
    echo "allowed-operation=NORMALIZE_REPRESENTATION"
    echo "allowed-operation=ORDER_DETERMINISTICALLY"
    echo "allowed-operation=ENCODE"
    echo "allowed-operation=WRITE_ARTIFACT"
    echo "non-goal=define-every-instruction-field"
    echo "non-goal=write-serializer"
    echo "non-goal=generate-bootstrap-ir"
    echo "non-goal=implement-equivalence-check"
    echo "next=B5.3-artifact-schema-contract"
    echo "format-contract-status=$format_contract_status"
    if [ "$format_contract_status" = DEFINED ]; then
        echo "verdict=SERIALIZATION_FORMAT_CONTRACT_DEFINED"
    else
        echo "verdict=SERIALIZATION_FORMAT_CONTRACT_BLOCKED"
    fi
} >"$report"

cat "$report"

if [ "$format_contract_status" = DEFINED ]; then
    exit 0
fi

exit 1
