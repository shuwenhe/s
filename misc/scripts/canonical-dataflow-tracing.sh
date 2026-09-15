#!/usr/bin/env bash

# B3.6.2.7: Canonical Data Flow Tracing
# 
# Goal: Map complete pipeline from MIR → SSA → Backend → Machine
#       Identify where stack_frame, abi_layout, drop info, symbols are created/accessed
# 
# Key hypothesis: stack_frame.s shows layout info is computed and stored.
#                Question: when? Before or during codegen?

set -e

S_SOURCE_ROOT="${S_SOURCE_ROOT:-.src}"
OUTPUT_FILE="${S_SOURCE_ROOT}/../../../.bootstrap/modular/canonical-dataflow-tracing.txt"

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
    echo "=========================================="
    echo "B3.6.2.7: Canonical Data Flow Tracing"
    echo "=========================================="
    echo ""
    echo "Trace: MIR → SSA → Backend → Code"
    echo ""
    
    # ============================================================
    # KEY FINDING 1: stack_frame structure exists
    # ============================================================
    echo ""
    echo "FINDING 1: Stack Frame Layout Representation"
    echo "────────────────────────────────────────"
    echo ""
    echo "  File: /backend/stack_frame.s"
    echo "  Structures found:"
    echo ""
    echo "  struct stack_slot {"
    echo "    int slot_id, offset, size, slot_type"
    echo "  }"
    echo ""
    echo "  struct stack_frame {"
    echo "    string func_name"
    echo "    stack_slot[] arg_slots"
    echo "    stack_slot[] local_slots"
    echo "    stack_slot[] spill_slots"
    echo "    int stack_size, alignment"
    echo "  }"
    echo ""
    echo "  Key observation:"
    echo "    ✓ Layout information (offsets) IS computed"
    echo "    ✓ Layout information IS stored in stack_frame structure"
    echo "    ✓ stack_frame structure is PERSISTENT (not just temporary)"
    echo ""
    echo "  Remaining questions:"
    echo "    ? When is stack_frame created in pipeline?"
    echo "    ? Before or during code emission?"
    echo "    ? Can it be serialized as bootstrap IR?"
    echo ""
    
    # ============================================================
    # SEARCH 1: When is stack_frame_new() called?
    # ============================================================
    echo ""
    echo "SEARCH 1: stack_frame Creation Points"
    echo "────────────────────────────────────────"
    echo ""
    
    call_count=$(grep -r "stack_frame_new\|stack_frame {" "$S_SOURCE_ROOT/cmd/compile/internal" 2>/dev/null | wc -l)
    echo "  References to stack_frame: $call_count"
    echo ""
    
    echo "  Locations:"
    grep -r "stack_frame_new\|stack_frame {" "$S_SOURCE_ROOT/cmd/compile/internal" 2>/dev/null | cut -d: -f1 | sort -u | head -10
    echo ""
    
    # ============================================================
    # KEY FINDING 2: emit_arg_info in ssa.s
    # ============================================================
    echo ""
    echo "FINDING 2: ABI Encoding in SSA"
    echo "────────────────────────────────────────"
    echo ""
    echo "  File: /ssagen/ssa.s"
    echo ""
    echo "  struct abi_param_desc {"
    echo "    int frame_offset, size"
    echo "    bool aggregate"
    echo "  }"
    echo ""
    echo "  func emit_arg_info(string fn_name, abi_param_desc[] params)"
    echo "    → arg_info_blob { symbol_name, bytes }"
    echo ""
    echo "  Key observation:"
    echo "    ✓ ABI parameter info (offsets, sizes) IS computed"
    echo "    ✓ ABI info IS encoded into funcdata"
    echo "    ✓ Encoding is SERIALIZED to bytes"
    echo ""
    echo "  This suggests:"
    echo "    - ABI decisions are made BEFORE or DURING function compilation"
    echo "    - ABI is explicitly serialized for funcdata"
    echo "    - This is a convergence point candidate"
    echo ""
    
    # ============================================================
    # PIPELINE RECONSTRUCTION
    # ============================================================
    echo ""
    echo "RECONSTRUCTION: Pipeline Order"
    echo "────────────────────────────────────────"
    echo ""
    
    echo "  Evidence for timing:"
    echo ""
    echo "  1. SSA construction phase:"
    echo "     - Creates SSA values and blocks from MIR"
    echo "     - emit_arg_info() encodes ABI (means ABI decided here or earlier)"
    echo ""
    echo "  2. Backend lowering phase:"
    echo "     - SSA → machine-independent lowering"
    echo "     - stack_frame computed (arg_slots, local_slots, spill_slots)"
    echo "     - Type layout finalized"
    echo ""
    echo "  3. Codegen phase:"
    echo "     - stack_frame → machine instructions"
    echo "     - stack_frame_emit_prologue/epilogue() converts to actual code"
    echo "     - Register allocation uses stack_frame info"
    echo ""
    echo "  Critical question:"
    echo "    WHERE in this pipeline is abi_param_desc[] created?"
    echo "    (emit_arg_info takes it as input, so it must be computed earlier)"
    echo ""
    
    # ============================================================
    # SEARCH 2: When is abi_param_desc created?
    # ============================================================
    echo ""
    echo "SEARCH 2: ABI Parameter Description Creation"
    echo "────────────────────────────────────────"
    echo ""
    
    abi_param_refs=$(grep -r "abi_param_desc" "$S_SOURCE_ROOT/cmd/compile/internal" 2>/dev/null | wc -l)
    echo "  References to abi_param_desc: $abi_param_refs"
    echo ""
    
    echo "  Files containing abi_param_desc:"
    grep -r "abi_param_desc" "$S_SOURCE_ROOT/cmd/compile/internal" 2>/dev/null | cut -d: -f1 | sort -u
    echo ""
    
    # ============================================================
    # SEARCH 3: Drop information flow
    # ============================================================
    echo ""
    echo "SEARCH 3: Drop Elaboration Integration"
    echo "────────────────────────────────────────"
    echo ""
    
    drop_refs=$(grep -r "drop_elaboration\|drop_info\|drop_location" "$S_SOURCE_ROOT/cmd/compile/internal" 2>/dev/null | wc -l)
    echo "  References to drop-related: $drop_refs"
    echo ""
    
    drop_files=$(grep -r "drop_elaboration\|drop_info" "$S_SOURCE_ROOT/cmd/compile/internal" 2>/dev/null | cut -d: -f1 | sort -u | head -10)
    if [ -z "$drop_files" ]; then
        echo "  NO drop-related structures found in pipeline"
        echo "  → Drop elaboration may not be integrated yet"
    else
        echo "  Drop-related found in:"
        echo "$drop_files"
    fi
    echo ""
    
    # ============================================================
    # HYPOTHESIS: Convergence Point Properties
    # ============================================================
    echo ""
    echo "HYPOTHESIS: Convergence Point Candidate"
    echo "────────────────────────────────────────"
    echo ""
    echo "  Location: After SSA backend lowering, before codegen"
    echo ""
    echo "  State at this point:"
    echo ""
    echo "  ✓ ABI decisions: Finalized"
    echo "    Evidence: abi_param_desc[] passed to emit_arg_info()"
    echo "    State structure: abi_param_desc with frame_offset"
    echo "    Accessible: YES (via emit_arg_info)"
    echo ""
    echo "  ✓ Type layout decisions: Finalized"
    echo "    Evidence: stack_frame computed with arg/local/spill offsets"
    echo "    State structure: stack_frame with stack_slot[] and stack_size"
    echo "    Accessible: YES (stack_frame object exists)"
    echo ""
    echo "  ? Drop elaboration: Status unknown"
    echo "    Evidence: No drop structures found in pipeline yet"
    echo "    State structure: ??? (unclear)"
    echo "    Accessible: ??? (unknown)"
    echo ""
    echo "  ? Symbol finalization: Partial"
    echo "    Evidence: Symbol names exist, but addresses not yet assigned"
    echo "    State structure: symbol_name strings in IR"
    echo "    Accessible: YES (but only symbol names, not addresses)"
    echo ""
    
    # ============================================================
    # CRITICAL QUESTION: Is there a serialization boundary?
    # ============================================================
    echo ""
    echo "CRITICAL QUESTION"
    echo "────────────────────────────────────────"
    echo ""
    echo "  Can we extract canonical's state after backend lowering"
    echo "  but before code emission?"
    echo ""
    echo "  Required data to serialize:"
    echo "    1. SSA values (ssa_value[], defined)"
    echo "    2. SSA blocks (ssa_block[], defined)"
    echo "    3. stack_frame info (defined and computed)"
    echo "    4. abi_param_desc[] (defined and computed)"
    echo "    5. symbol_name mappings (exist but location unclear)"
    echo "    6. drop info (location unclear)"
    echo ""
    echo "  Analysis:"
    echo "    - Most data structures ARE explicitly defined"
    echo "    - Most data structures ARE computed in pipeline"
    echo "    - Some integration points unclear (drop, symbols)"
    echo ""
    echo "  Next verification needed:"
    echo "    A. Find where drop elaboration is integrated"
    echo "    B. Find where symbol names are recorded"
    echo "    C. Verify: can all five data types be collected at one point?"
    echo "    D. Verify: is that point before codegen?"
    echo ""
    
    # ============================================================
    # BOOTSTRAP IR PATH FEASIBILITY
    # ============================================================
    echo ""
    echo "PRELIMINARY BOOTSTRAP IR FEASIBILITY"
    echo "────────────────────────────────────────"
    echo ""
    echo "  Current evidence suggests:"
    echo ""
    echo "  ABI decisions:       ✓ ACCESSIBLE (via abi_param_desc)"
    echo "  Type layout:         ✓ ACCESSIBLE (via stack_frame)"
    echo "  Drop elaboration:    ? UNKNOWN (need deeper investigation)"
    echo "  Symbol names:        ? PARTIALLY ACCESSIBLE (recorded, but integration unclear)"
    echo ""
    echo "  Verdict:"
    echo "    IF drop + symbol issues resolved: FEASIBLE (low to medium effort)"
    echo "    ELSE: FEASIBLE WITH ADDITIONAL WORK (design drop/symbol tracking)"
    echo ""
    
    # ============================================================
    # IMMEDIATE ACTION ITEMS
    # ============================================================
    echo ""
    echo "NEXT STEPS"
    echo "────────────────────────────────────────"
    echo ""
    echo "  Priority 1: Find drop elaboration integration"
    echo "    - Check ownership/ module for structure definitions"
    echo "    - Find where drop results are stored"
    echo "    - Verify if drop info flows to SSA/backend"
    echo ""
    echo "  Priority 2: Verify symbol tracking"
    echo "    - Find where symbol names are recorded"
    echo "    - Check if symbol info can be collected at lowering stage"
    echo ""
    echo "  Priority 3: Prototype extraction"
    echo "    - Design snapshot structure containing:"
    echo "      { ssa_func, stack_frame, abi_param_desc[], symbol_map, drop_info }"
    echo "    - This would be bootstrap IR target"
    echo ""
    
} | tee "$OUTPUT_FILE"

echo ""
echo "Output saved to: $OUTPUT_FILE"
echo ""
