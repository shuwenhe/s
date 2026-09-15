#!/usr/bin/env bash

# B3.6.1: Canonical MIR Bootstrap Sufficiency Audit
# Purpose: Determine if canonical MIR is ready for structural serialization
# to bootstrap IR, or if additional lowering is needed in canonical

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S_PROJECT_ROOT="${S_PROJECT_ROOT:-.}"
S_SOURCE_ROOT="${S_SOURCE_ROOT:-$S_PROJECT_ROOT/src}"
CANONICAL_IR_DIR="${S_SOURCE_ROOT}/cmd/compile/internal/ir"

# Output directory
AUDIT_OUTPUT="${S_PROJECT_ROOT}/.bootstrap/modular/mir-bootstrap-sufficiency-audit.txt"
mkdir -p "$(dirname "$AUDIT_OUTPUT")"

{
    echo "=========================================="
    echo "B3.6.1: Canonical MIR Bootstrap Sufficiency Audit"
    echo "=========================================="
    echo ""
    echo "Audit Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Canonical IR Directory: $CANONICAL_IR_DIR"
    echo ""

    # ========================================
    # 1. Type Layout Finalization Check
    # ========================================
    echo ">>> 1. Type Layout Finalization Check"
    echo ""
    
    # Look for field offset information in type definitions
    has_field_offset=$(grep -r "offset" "$CANONICAL_IR_DIR" | grep -i "field\|struct" | wc -l)
    has_type_size=$(grep -r "size\|Size" "$CANONICAL_IR_DIR" | grep -i "struct\|type" | wc -l)
    has_alignment=$(grep -r "align\|Align" "$CANONICAL_IR_DIR" | grep -i "struct\|field" | wc -l)
    
    echo "Evidence Collection:"
    echo "  - Field offset references: $has_field_offset"
    echo "  - Type size references: $has_type_size"
    echo "  - Alignment references: $has_alignment"
    echo ""
    
    # Check mir.s specifically
    echo "Checking mir.s for layout information..."
    if grep -q "struct mir_local_slot" "$CANONICAL_IR_DIR/mir.s"; then
        echo "  Found mir_local_slot definition"
        mir_local_slots=$(sed -n '/struct mir_local_slot/,/^}/p' "$CANONICAL_IR_DIR/mir.s" || true)
        echo "  Structure content:"
        echo "$mir_local_slots" | sed 's/^/    /'
        
        if echo "$mir_local_slots" | grep -q "offset\|byte_offset"; then
            echo "  ✓ Field offsets found in mir_local_slot"
            type_layout_finalized="YES"
            type_layout_evidence="mir_local_slot has offset/byte_offset fields"
        else
            echo "  ✗ No offset fields in mir_local_slot (only type_name: option[string])"
            type_layout_finalized="NO"
            type_layout_evidence="mir_local_slot missing offset/byte_offset, layout deferred"
        fi
    else
        type_layout_finalized="UNKNOWN"
        type_layout_evidence="mir_local_slot not found, cannot determine"
    fi
    echo ""
    
    # ========================================
    # 2. ABI Decisions Finalization Check
    # ========================================
    echo ">>> 2. ABI Decisions Finalization Check"
    echo ""
    
    echo "Looking for Call/function representation in MIR..."
    call_struct_found=$(grep -r "struct.*call\|struct.*Call\|struct.*CALL" "$CANONICAL_IR_DIR" | wc -l)
    echo "  Call structure definitions found: $call_struct_found"
    
    # Check for ABI-related fields
    echo "Looking for ABI information (calling_convention, register, stack)..."
    abi_info=$(grep -r "calling_convention\|register\|stack_slot\|arg_location" "$CANONICAL_IR_DIR" | wc -l)
    echo "  ABI information references: $abi_info"
    echo ""
    
    # Check ir/abi.s
    echo "Checking ir/abi.s..."
    if [ -f "$CANONICAL_IR_DIR/abi.s" ]; then
        abi_content=$(wc -l < "$CANONICAL_IR_DIR/abi.s")
        echo "  abi.s line count: $abi_content"
        if [ "$abi_content" -lt 10 ]; then
            abi_decisions_finalized="NO"
            abi_evidence="abi.s exists but nearly empty (< 10 lines), no real implementation"
        else
            # Check if it has actual implementation
            if grep -q "func.*abi\|struct.*abi" "$CANONICAL_IR_DIR/abi.s"; then
                abi_decisions_finalized="YES"
                abi_evidence="abi.s has function/struct definitions"
            else
                abi_decisions_finalized="NO"
                abi_evidence="abi.s has only module declarations, no implementation"
            fi
        fi
    else
        abi_decisions_finalized="UNKNOWN"
        abi_evidence="abi.s not found"
    fi
    echo "  Result: abi-decisions-finalized=$abi_decisions_finalized"
    echo ""
    
    # ========================================
    # 3. Drop Elaboration Completeness Check
    # ========================================
    echo ">>> 3. Drop Elaboration Completeness Check"
    echo ""
    
    echo "Looking for drop-related MIR constructs..."
    drop_count=$(grep -r "drop\|Drop\|DROP" "$CANONICAL_IR_DIR/mir.s" 2>/dev/null | wc -l)
    echo "  Drop references in mir.s: $drop_count"
    
    # Check if mir.s has ownership/drop information
    if grep -q "mir_statement\|mir.*drop" "$CANONICAL_IR_DIR/mir.s" 2>/dev/null; then
        mir_stmt_content=$(sed -n '/enum mir_statement/,/^}/p' "$CANONICAL_IR_DIR/mir.s" || true)
        echo "  mir_statement enum content:"
        echo "$mir_stmt_content" | sed 's/^/    /'
        
        if echo "$mir_stmt_content" | grep -q "drop\|Drop"; then
            drop_elaboration_complete="YES"
            drop_evidence="mir_statement has drop variant"
        else
            drop_elaboration_complete="NO"
            drop_evidence="mir_statement lacks drop variant, ownership not elaborated"
        fi
    else
        # Check if there's separate drop handling
        drop_files=$(find "$CANONICAL_IR_DIR" -name "*drop*" -o -name "*ownership*" | wc -l)
        if [ "$drop_files" -gt 0 ]; then
            drop_elaboration_complete="UNKNOWN"
            drop_evidence="Drop handling in separate files ($drop_files), need inspection"
        else
            drop_elaboration_complete="NO"
            drop_evidence="No drop-related code found in MIR, ownership not elaborated in MIR"
        fi
    fi
    echo "  Result: drop-elaboration-complete=$drop_elaboration_complete"
    echo ""
    
    # ========================================
    # 4. Symbol Bindings Resolution Check
    # ========================================
    echo ">>> 4. Symbol Bindings Resolution Check"
    echo ""
    
    echo "Looking for symbol resolution in MIR..."
    # Check for concrete function references (indices, IDs) vs string names
    func_id_refs=$(grep -r "func.*id\|func_id\|function_id" "$CANONICAL_IR_DIR/mir.s" 2>/dev/null | wc -l)
    func_name_refs=$(grep -r "func.*name\|function.*name" "$CANONICAL_IR_DIR/mir.s" 2>/dev/null | wc -l)
    
    echo "  Function ID references: $func_id_refs"
    echo "  Function name references: $func_name_refs"
    echo ""
    
    # Check ir_function structure
    if grep -q "struct ir_function\|func ir_function" "$CANONICAL_IR_DIR/mir.s" 2>/dev/null; then
        ir_func_content=$(sed -n '/struct ir_function/,/^}/p' "$CANONICAL_IR_DIR/mir.s" || true)
        echo "  ir_function structure content:"
        echo "$ir_func_content" | sed 's/^/    /'
        
        # Check if functions are referenced by ID or name
        if echo "$ir_func_content" | grep -q "func.*id\|function.*id"; then
            symbol_bindings_resolved="YES"
            symbol_binding_evidence="ir_function uses concrete IDs for function references"
        else
            symbol_bindings_resolved="UNKNOWN"
            symbol_binding_evidence="Cannot determine from ir_function structure, unclear how calls are represented"
        fi
    else
        symbol_bindings_resolved="UNKNOWN"
        symbol_binding_evidence="ir_function structure not found in mir.s"
    fi
    echo "  Result: symbol-bindings-resolved=$symbol_bindings_resolved"
    echo ""
    
    # ========================================
    # Final Decision
    # ========================================
    echo "=========================================="
    echo "AUDIT RESULTS"
    echo "=========================================="
    echo ""
    echo "type-layout-finalized=$type_layout_finalized"
    echo "type-layout-evidence=$type_layout_evidence"
    echo ""
    echo "abi-decisions-finalized=$abi_decisions_finalized"
    echo "abi-decisions-evidence=$abi_evidence"
    echo ""
    echo "drop-elaboration-complete=$drop_elaboration_complete"
    echo "drop-elaboration-evidence=$drop_evidence"
    echo ""
    echo "symbol-bindings-resolved=$symbol_bindings_resolved"
    echo "symbol-bindings-evidence=$symbol_binding_evidence"
    echo ""
    
    # Mechanical decision logic
    echo "=========================================="
    echo "DECISION LOGIC"
    echo "=========================================="
    echo ""
    
    # Count YES, NO, UNKNOWN
    yes_count=0
    no_count=0
    unknown_count=0
    
    for val in "$type_layout_finalized" "$abi_decisions_finalized" "$drop_elaboration_complete" "$symbol_bindings_resolved"; do
        if [ "$val" = "YES" ]; then
            ((yes_count++))
        elif [ "$val" = "NO" ]; then
            ((no_count++))
        elif [ "$val" = "UNKNOWN" ]; then
            ((unknown_count++))
        fi
    done
    
    echo "Counts: YES=$yes_count, NO=$no_count, UNKNOWN=$unknown_count"
    echo ""
    
    if [ "$no_count" -eq 0 ] && [ "$unknown_count" -eq 0 ]; then
        mir_bootstrap_sufficiency="SUFFICIENT"
        first_missing_lowering="NONE"
    elif [ "$no_count" -gt 0 ]; then
        mir_bootstrap_sufficiency="INSUFFICIENT"
        # Find first missing capability
        if [ "$type_layout_finalized" = "NO" ]; then
            first_missing_lowering="canonical-type-layout-lowering"
        elif [ "$abi_decisions_finalized" = "NO" ]; then
            first_missing_lowering="canonical-abi-lowering"
        elif [ "$drop_elaboration_complete" = "NO" ]; then
            first_missing_lowering="canonical-drop-elaboration"
        else
            first_missing_lowering="unknown-missing-capability"
        fi
    else
        mir_bootstrap_sufficiency="NOT_PROVEN"
        first_missing_lowering="undetermined-due-to-unknowns"
    fi
    
    echo "mir-bootstrap-sufficiency=$mir_bootstrap_sufficiency"
    echo "first-missing-lowering-capability=$first_missing_lowering"
    echo ""
    
    # ========================================
    # Recommendations
    # ========================================
    echo "=========================================="
    echo "RECOMMENDATIONS"
    echo "=========================================="
    echo ""
    
    if [ "$mir_bootstrap_sufficiency" = "SUFFICIENT" ]; then
        echo "✓ Canonical MIR is sufficiently lowered"
        echo "  → Proceed to B3.6.2 (MIR→IR mapping contract design)"
        echo "  → Adapter can be purely structural"
    else
        echo "✗ Canonical MIR is NOT sufficiently lowered"
        echo "  → Missing capability: $first_missing_lowering"
        echo "  → Do NOT design structural adapter yet"
        echo "  → Instead: canonical needs additional lowering layer"
        echo "  → New path:"
        echo "     canonical MIR (semantic)"
        echo "         ↓"
        echo "     canonical $first_missing_lowering pass"
        echo "         ↓"
        echo "     lowered-MIR / LIR (all decisions final)"
        echo "         ↓"
        echo "     (then structural adapter on this)"
    fi
    echo ""
    
    if [ "$mir_bootstrap_sufficiency" = "NOT_PROVEN" ]; then
        echo "⚠ Audit inconclusive (UNKNOWN values)"
        echo "  → Get clarity on MIR representation"
        echo "  → Document what each MIR node contains"
        echo "  → Re-run audit with clear understanding"
    fi
    echo ""
    
    echo "=========================================="
    echo "Audit complete. Results saved to:"
    echo "  $AUDIT_OUTPUT"
    echo "=========================================="

} | tee "$AUDIT_OUTPUT"

# Export results for makefile/caller
export_results() {
    echo "mir-bootstrap-sufficiency=$mir_bootstrap_sufficiency"
    echo "first-missing-lowering-capability=$first_missing_lowering"
}

# Print results at end
export_results
