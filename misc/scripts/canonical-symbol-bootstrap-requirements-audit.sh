#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${CANONICAL_SYMBOL_BOOTSTRAP_REQUIREMENTS_AUDIT_REPORT:-"$root/.bootstrap/modular/canonical-symbol-bootstrap-requirements-audit.txt"}

mkdir -p "$(dirname -- "$report")"

has_text() {
    pattern=$1
    shift
    for path in "$@"; do
        if rg -q "$pattern" "$root/$path" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

seed_ir_symbol_requirement=UNKNOWN
if has_text 'CALL\\|.*\\|.*\\|' src/cmd/compile/seed/stage1.ir src/cmd/compile/seed/stage2.ir; then
    seed_ir_symbol_requirement=NAME
fi

consumer_performs_relocation=UNKNOWN
if has_text 'relocation|R_X86_64|PLT|GOT|CALL' src/cmd/compile/seed/code src/cmd/compile/seed/runtime; then
    consumer_performs_relocation=YES
fi

consumer_performs_address_assignment=UNKNOWN
if has_text 'emit_aot_from_ir_file|emit_standalone_amd64_from_ir_file|gcc .* -o|runtime_execute_text' src/cmd/compile/seed; then
    consumer_performs_address_assignment=YES
fi

canonical_semantic_symbol_identity=NO
if has_text 'resolved_callee|symbol_table|check_source_file|method resolution|package symbol' src/cmd/compile/internal; then
    canonical_semantic_symbol_identity=YES
fi

canonical_linker_symbol_state=UNKNOWN
if has_text 'normalize_go_symbol|link_symbol|emit_link_manifest|build_link_symbols|relocation_entry.*symbol' src/cmd/compile/internal; then
    canonical_linker_symbol_state=PARTIAL
fi

canonical_final_address_state=NOT_REQUIRED_OR_NOT_PROVEN
if has_text 'resolved_address|load_base|symbol_value|address assignment' src/cmd/compile/internal/linker src/cmd/compile/internal/link; then
    canonical_final_address_state=NOT_REQUIRED_OR_PARTIAL
fi

canonical_symbol_state_at_snapshot=UNKNOWN
symbol_state_sufficient=NO
if [ "$seed_ir_symbol_requirement" = NAME ] && [ "$canonical_semantic_symbol_identity" = YES ]; then
    canonical_symbol_state_at_snapshot=SYMBOL_NAME_AND_SEMANTIC_IDENTITY
    symbol_state_sufficient=YES
fi

{
    echo "canonical-symbol-bootstrap-requirements-audit"
    echo "purpose=read-only-symbol-requirement-audit"
    echo "symbol-distinction=semantic-symbol-identity != linker-symbol != final-machine-address"
    echo "seed-ir-symbol-requirement=$seed_ir_symbol_requirement"
    echo "canonical-symbol-state-at-snapshot=$canonical_symbol_state_at_snapshot"
    echo "canonical-semantic-symbol-identity=$canonical_semantic_symbol_identity"
    echo "canonical-linker-symbol-state=$canonical_linker_symbol_state"
    echo "canonical-final-address-state=$canonical_final_address_state"
    echo "consumer-performs-relocation=$consumer_performs_relocation"
    echo "consumer-performs-address-assignment=$consumer_performs_address_assignment"
    echo "final-address-required-from-canonical-producer=NO"
    echo "symbol-state-sufficient=$symbol_state_sufficient"
    echo "non-goal=final-address-assignment-in-snapshot"
    echo "non-goal=implement-symbol-serializer"
    if [ "$symbol_state_sufficient" = YES ]; then
        echo "verdict=SYMBOL_BOOTSTRAP_REQUIREMENTS_SUFFICIENT"
    else
        echo "verdict=SYMBOL_BOOTSTRAP_REQUIREMENTS_NOT_PROVEN"
    fi
} >"$report"

cat "$report"

exit 0
