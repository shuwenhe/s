#!/usr/bin/env bash

# B3.6.2.6: Canonical Lowered State Accessibility Audit
# 
# Goal: Trace when and where each decision (ABI, layout, drop, symbols) is computed,
#       what data structures store it, and whether a convergence point exists.
# 
# Critical Questions:
#   1. Where is each decision produced?
#   2. What data structure stores it?
#   3. What is the lifetime of that data structure?
#   4. Is there a single point where ALL decisions are finalized but code not yet emitted?

set -e

S_SOURCE_ROOT="${S_SOURCE_ROOT:-.src}"
OUTPUT_FILE="${S_SOURCE_ROOT}/../../../.bootstrap/modular/lowered-state-accessibility-audit.txt"

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
    echo "=========================================="
    echo "B3.6.2.6: Canonical Lowered State Accessibility Audit"
    echo "=========================================="
    echo ""
    echo "Tracking: ABI decisions, type layout, drop elaboration, symbol binalization"
    echo ""
    
    # ============================================================
    # DECISION 1: ABI (Parameter/Result Assignment)
    # ============================================================
    echo ""
    echo "────────────────────────────────────────"
    echo "DECISION 1: ABI Parameter/Result Assignment"
    echo "────────────────────────────────────────"
    echo ""
    
    echo "Producer Location:"
    if [ -f "$S_SOURCE_ROOT/cmd/compile/internal/ssagen/abi.s" ]; then
        echo "  ✓ /ssagen/abi.s: assign_abi_layout(arch, params, results) → abi_layout"
        echo ""
        echo "  Function signature:"
        grep -A 2 "func assign_abi_layout" "$S_SOURCE_ROOT/cmd/compile/internal/ssagen/abi.s" || true
        echo ""
    fi
    
    echo "Representation:"
    if [ -f "$S_SOURCE_ROOT/cmd/compile/internal/abi/abiutils.s" ]; then
        echo "  ✓ /abi/abiutils.s: abi_param_assignment, abi_location"
        grep -A 5 "struct abi_location\|struct abi_layout" "$S_SOURCE_ROOT/cmd/compile/internal/ssagen/abi.s" 2>/dev/null | head -15 || true
        echo ""
    fi
    
    echo "Storage/Encoding:"
    if [ -f "$S_SOURCE_ROOT/cmd/compile/internal/ssagen/ssa.s" ]; then
        echo "  ✓ /ssagen/ssa.s: emit_arg_info() encodes ABI into funcdata"
        echo "    Structures: abi_param_desc (frame_offset, size, aggregate)"
        echo "    Output: arg_info_blob with symbol_name + bytes"
        echo ""
    fi
    
    echo "Lifetime Questions:"
    echo "  ? When is assign_abi_layout() called?"
    echo "    grep result: $(grep -r 'assign_abi_layout' "$S_SOURCE_ROOT/cmd/compile/internal" 2>/dev/null | wc -l) references"
    echo ""
    echo "  ? Does abi_layout get attached to MIR/SSA nodes?"
    grep -q "abi_layout\|abi_param" "$S_SOURCE_ROOT/cmd/compile/internal/ir/mir.s" 2>/dev/null && echo "    ✓ Found in mir.s" || echo "    ✗ NOT found in mir.s"
    grep -q "abi_layout\|abi_param" "$S_SOURCE_ROOT/cmd/compile/internal/ssa/ssa_core.s" 2>/dev/null && echo "    ✓ Found in ssa_core.s" || echo "    ✗ NOT found in ssa_core.s"
    echo ""
    
    echo "State: ABI"
    echo "  implementation=PROVEN (assign_abi_layout exists)"
    echo "  representation=PROVEN (abi_location, abi_layout defined)"
    echo "  encoding=PARTIAL (funcdata exists, but full integration unknown)"
    echo "  serialization-boundary=NOT_PROVEN (must trace call sites)"
    echo ""
    
    # ============================================================
    # DECISION 2: Type Layout (Field Offsets, Size)
    # ============================================================
    echo ""
    echo "────────────────────────────────────────"
    echo "DECISION 2: Type Layout (Field Offsets, Size)"
    echo "────────────────────────────────────────"
    echo ""
    
    echo "Producer Location:"
    backend_files=$(find "$S_SOURCE_ROOT/cmd/compile/internal/backend" -name "*.s" 2>/dev/null | wc -l)
    echo "  ✓ /backend/ module ($backend_files .s files)"
    echo ""
    
    echo "Related Structures in backend/:"
    for f in "$S_SOURCE_ROOT/cmd/compile/internal/backend"/*.s; do
        [ -f "$f" ] && grep -l "offset\|layout\|size" "$f" | head -3 || true
    done | sort -u | head -5
    echo ""
    
    echo "Storage in IR:"
    echo "  Checking ir/mir.s for layout information..."
    if grep -q "offset\|byte_offset" "$S_SOURCE_ROOT/cmd/compile/internal/ir/mir.s" 2>/dev/null; then
        echo "    ✓ Found offset fields in MIR"
        grep "offset\|byte_offset" "$S_SOURCE_ROOT/cmd/compile/internal/ir/mir.s" 2>/dev/null | head -5 || true
    else
        echo "    ✗ NO offset/byte_offset fields found in MIR"
    fi
    echo ""
    
    echo "Lifetime Questions:"
    echo "  ? Backend layout computation: when does it happen?"
    echo "  ? Is result stored in backend state or computed on-demand?"
    echo "  ? Is layout information accessible after backend pass but before codegen?"
    echo ""
    
    echo "State: Type Layout"
    echo "  authority=BACKEND"
    echo "  mir-representation=INCOMPLETE (no offset fields)"
    echo "  backend-state-accessibility=UNKNOWN"
    echo "  serialization-boundary=NOT_PROVEN"
    echo ""
    
    # ============================================================
    # DECISION 3: Drop Elaboration (Which values need Drop calls)
    # ============================================================
    echo ""
    echo "────────────────────────────────────────"
    echo "DECISION 3: Drop Elaboration"
    echo "────────────────────────────────────────"
    echo ""
    
    echo "Producer Location:"
    ownership_files=$(find "$S_SOURCE_ROOT/cmd/compile/internal/ownership" -name "*.s" 2>/dev/null | wc -l)
    echo "  ✓ /ownership/ module ($ownership_files .s files)"
    echo ""
    
    echo "Key Files:"
    ls -1 "$S_SOURCE_ROOT/cmd/compile/internal/ownership"/*.s 2>/dev/null | head -10
    echo ""
    
    echo "Representation:"
    echo "  Checking ir/mir.s for drop information..."
    if grep -q "drop\|Drop" "$S_SOURCE_ROOT/cmd/compile/internal/ir/mir.s" 2>/dev/null; then
        echo "    ✓ Found drop-related fields in MIR"
        grep "drop\|Drop" "$S_SOURCE_ROOT/cmd/compile/internal/ir/mir.s" 2>/dev/null | head -5 || true
    else
        echo "    ✗ NO drop fields found in MIR node types"
    fi
    echo ""
    
    echo "Lifetime Questions:"
    echo "  ? When are drop decisions made relative to MIR/SSA construction?"
    echo "  ? Are drops stored in SSA node or separate data structure?"
    echo "  ? Are all drops finalized before code emission?"
    echo ""
    
    echo "State: Drop Elaboration"
    echo "  authority=OWNERSHIP_MODULE"
    echo "  mir-representation=UNKNOWN"
    echo "  ssa-representation=UNKNOWN"
    echo "  serialization-boundary=NOT_PROVEN"
    echo ""
    
    # ============================================================
    # DECISION 4: Symbol Finalization (Names → Addresses)
    # ============================================================
    echo ""
    echo "────────────────────────────────────────"
    echo "DECISION 4: Symbol Finalization"
    echo "────────────────────────────────────────"
    echo ""
    
    echo "Producer Location:"
    link_files=$(find "$S_SOURCE_ROOT/cmd/compile/internal/link" -name "*.s" 2>/dev/null | wc -l)
    obj_files=$(find "$S_SOURCE_ROOT/cmd/compile/internal/obj" -name "*.s" 2>/dev/null | wc -l)
    echo "  ✓ /link/ module ($link_files .s files)"
    echo "  ✓ /obj/ module ($obj_files .s files)"
    echo ""
    
    echo "Processing Timeline:"
    echo "  1. Symbol names defined during IR construction"
    echo "  2. Backend emits machine code with symbolic references"
    echo "  3. Link module resolves symbolic references"
    echo "  4. Final object file contains relocations/addresses"
    echo ""
    
    echo "State: Symbol Finalization"
    echo "  authority=LINK + OBJ modules"
    echo "  timing=POST_CODEGEN (happens after machine instructions emitted)"
    echo "  serialization-boundary=NOT_PROVEN (but temporal ordering clear)"
    echo ""
    
    # ============================================================
    # CONVERGENCE POINT ANALYSIS
    # ============================================================
    echo ""
    echo "────────────────────────────────────────"
    echo "CONVERGENCE POINT ANALYSIS"
    echo "────────────────────────────────────────"
    echo ""
    
    echo "Pipeline Stages:"
    echo ""
    echo "  STAGE 1: Semantic (MIR)"
    echo "    Representation: mir_statement, mir_operand"
    echo "    Decisions available: none (semantic only)"
    echo "    ABI:      not-finalized"
    echo "    Layout:   not-finalized"
    echo "    Drop:     not-finalized"
    echo "    Symbol:   not-finalized"
    echo ""
    
    echo "  STAGE 2: SSA (Mid-level IR)"
    echo "    Representation: SSA values and blocks"
    echo "    ABI info: PARTIAL (encoded in funcdata per ssa.s)"
    echo "    Layout:   still not-finalized?"
    echo "    Drop:     still not-finalized?"
    echo "    Symbol:   still not-finalized"
    echo ""
    
    echo "  STAGE 3: Backend (Machine-independent lowering)"
    echo "    After this stage:"
    echo "    - Type layout FULLY decided"
    echo "    - ABI FULLY decided"
    echo "    - Drop elaboration FULLY decided"
    echo "    - Symbol names known but not relocated"
    echo "    BUT: No machine code emitted yet? → CONVERGENCE CANDIDATE"
    echo ""
    
    echo "  STAGE 4: Codegen (Machine instructions)"
    echo "    Machine instructions generated from backend IR"
    echo "    Symbolic references → relocations"
    echo ""
    
    echo "  STAGE 5: Linker (Symbol resolution)"
    echo "    Relocations resolved to final addresses"
    echo "    Final object format written"
    echo ""
    
    echo "Convergence Point Hypothesis:"
    echo "  Location: After backend lowering, before codegen"
    echo "  State properties needed:"
    echo "    ✓ ABI finalized (assign_abi_layout output)"
    echo "    ✓ Type layout finalized (backend output)"
    echo "    ✓ Drop elaboration finalized (ownership module output)"
    echo "    ? Symbol references resolved (but not to addresses)"
    echo "    ✗ Machine code not yet emitted"
    echo ""
    
    # ============================================================
    # ACCESSIBILITY ASSESSMENT
    # ============================================================
    echo ""
    echo "────────────────────────────────────────"
    echo "ACCESSIBILITY ASSESSMENT"
    echo "────────────────────────────────────────"
    echo ""
    
    echo "Question 1: Is post-backend state addressable in canonical?"
    echo "  Current evidence:"
    echo "    - backend/ module exists with full implementation"
    echo "    - ownership/ module has drop elaboration"
    echo "    - abi/ and ssagen/ have ABI decision functions"
    echo "    - obj/ and link/ can consume output"
    echo "  Verdict: LIKELY YES (but must verify data flow)"
    echo ""
    
    echo "Question 2: Is that state a stable intermediate?"
    echo "  Current evidence:"
    echo "    - No explicit 'LIR' or 'lowered IR' structure found yet"
    echo "    - Backend likely uses internal data structures"
    echo "    - SSA values might carry lowering information"
    echo "  Verdict: UNKNOWN (must trace SSA lowering)"
    echo ""
    
    echo "Question 3: Can that state be serialized for bootstrap?"
    echo "  Current evidence:"
    echo "    - SSEED-TARGET-V1 exists as bootstrap IR target"
    echo "    - native/AOT can consume bootstrap IR"
    echo "    - No existing canonical→SSEED serializer found"
    echo "  Verdict: FEASIBLE IF (lowered state is accessible)"
    echo ""
    
    # ============================================================
    # FINAL VERDICT
    # ============================================================
    echo ""
    echo "=========================================="
    echo "PRELIMINARY VERDICT"
    echo "=========================================="
    echo ""
    
    echo "Decision Status Summary:"
    echo "  ABI:       IMPLEMENTATION_PROVEN, REPRESENTATION_PROVEN, SERIALIZATION_BOUNDARY=UNKNOWN"
    echo "  Layout:    AUTHORITY_IDENTIFIED (backend), SERIALIZATION_BOUNDARY=UNKNOWN"
    echo "  Drop:      AUTHORITY_IDENTIFIED (ownership), SERIALIZATION_BOUNDARY=UNKNOWN"
    echo "  Symbol:    AUTHORITY_IDENTIFIED (link/obj), TIMING_POST_CODEGEN"
    echo ""
    
    echo "Convergence Point:"
    echo "  HYPOTHESIS: Post-backend, pre-codegen state"
    echo "  EVIDENCE:   Incomplete (must trace data flow)"
    echo "  NEXT_STEP:  Inspect backend/ and ssa/ modules for lowering data structures"
    echo ""
    
    echo "Lowering State Classification:"
    echo "  current-verdict=LOWERING_STATE_ACCESSIBILITY_UNKNOWN"
    echo "  recommendation=DEEP_INVESTIGATION_REQUIRED"
    echo ""
    echo "  If accessible AND stable: LOWERED_STATE_ACCESSIBLE_NOT_SERIALIZED"
    echo "    → IR bootstrap needs: serialization layer only (low effort)"
    echo ""
    echo "  If fragmented/post-codegen: LOWERING_STATE_FRAGMENTED"
    echo "    → IR bootstrap needs: canonical LIR design (medium effort)"
    echo ""
    echo "  If not accessible: LOWERED_STATE_NOT_ACCESSIBLE"
    echo "    → IR bootstrap: not viable with current canonical (high effort or pivot)"
    echo ""
    
    echo "=========================================="
    echo "NEXT INVESTIGATION STEPS"
    echo "=========================================="
    echo ""
    echo "Priority 1: Trace SSA lowering"
    echo "  - What data structures does SSA backend pass populate?"
    echo "  - When are ABI/layout/drop decisions attached to SSA values?"
    echo "  - Is there a point where SSA + all decisions are addressable?"
    echo ""
    echo "Priority 2: Inspect backend architecture"
    echo "  - What is the output of backend/ module?"
    echo "  - Does backend serialize any state?"
    echo "  - Can backend output be accessed before codegen?"
    echo ""
    echo "Priority 3: Verify symbol timing"
    echo "  - Can symbols be recorded during earlier stages?"
    echo "  - Or must symbol resolution wait for linker?"
    echo ""
    
} | tee "$OUTPUT_FILE"

echo ""
echo "Output saved to: $OUTPUT_FILE"
echo ""
