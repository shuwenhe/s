#!/usr/bin/env bash

# B3.6.2: Canonical Post-MIR Lowering Authority Audit
# Purpose: Locate where canonical currently makes lowering decisions
# that B3.6.1 found missing from MIR representation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S_PROJECT_ROOT="${S_PROJECT_ROOT:-.}"
S_SOURCE_ROOT="${S_SOURCE_ROOT:-$S_PROJECT_ROOT/src}"
CANONICAL_BACKEND_DIR="${S_SOURCE_ROOT}/cmd/compile/internal/backend"
CANONICAL_OBJ_DIR="${S_SOURCE_ROOT}/cmd/compile/internal/obj"
CANONICAL_SSA_DIR="${S_SOURCE_ROOT}/cmd/compile/internal/ssa"

# Output directory
AUDIT_OUTPUT="${S_PROJECT_ROOT}/.bootstrap/modular/post-mir-lowering-authority-audit.txt"
mkdir -p "$(dirname "$AUDIT_OUTPUT")"

{
    echo "=========================================="
    echo "B3.6.2: Canonical Post-MIR Lowering Authority Audit"
    echo "=========================================="
    echo ""
    echo "Audit Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Canonical Backend Directory: $CANONICAL_BACKEND_DIR"
    echo "Canonical OBJ Directory: $CANONICAL_OBJ_DIR"
    echo "Canonical SSA Directory: $CANONICAL_SSA_DIR"
    echo ""
    echo "Purpose: Locate where decisions are made for:"
    echo "  - Type layout (field offsets, struct size, alignment)"
    echo "  - ABI decisions (calling convention, register/stack assignment)"
    echo "  - Drop elaboration (ownership cleanup sequences)"
    echo "  - Symbol finalization (name → address mapping)"
    echo ""

    # ========================================
    # 1. Type Layout Authority
    # ========================================
    echo ">>> 1. Type Layout Authority"
    echo ""
    echo "Q: Where are field offsets computed?"
    echo ""
    
    # Search for layout computation
    layout_in_mir=$(grep -r "offset\|byte_offset\|field.*size" "$CANONICAL_OBJ_DIR" 2>/dev/null | wc -l)
    layout_in_ssa=$(grep -r "offset\|byte_offset\|field.*size" "$CANONICAL_SSA_DIR" 2>/dev/null | wc -l)
    layout_in_backend=$(grep -r "offset\|byte_offset\|field.*size" "$CANONICAL_BACKEND_DIR" 2>/dev/null | wc -l)
    
    echo "  References in obj/: $layout_in_ssa"
    echo "  References in ssa/: $layout_in_ssa"
    echo "  References in backend/: $layout_in_backend"
    echo ""
    
    # Check for struct layout or type info modules
    if [ -f "$CANONICAL_OBJ_DIR/staticdata.s" ]; then
        echo "  Found: obj/staticdata.s (likely contains static data layout)"
        if grep -q "struct\|layout\|offset" "$CANONICAL_OBJ_DIR/staticdata.s" 2>/dev/null; then
            layout_authority="BACKEND"
            layout_evidence="obj/staticdata.s contains layout/offset handling"
        else
            layout_authority="UNKNOWN"
            layout_evidence="obj/staticdata.s exists but content unclear"
        fi
    elif [ -f "$CANONICAL_BACKEND_DIR/backend.s" ]; then
        echo "  Found: backend/backend.s (generic backend)"
        layout_authority="BACKEND"
        layout_evidence="backend.s likely handles layout"
    else
        layout_authority="UNKNOWN"
        layout_evidence="No obvious layout authority module found"
    fi
    echo ""
    
    # ========================================
    # 2. ABI Decisions Authority
    # ========================================
    echo ">>> 2. ABI Decisions Authority"
    echo ""
    echo "Q: Where are calling conventions and register assignments decided?"
    echo ""
    
    # Search for ABI/calling convention code
    abi_in_obj=$(grep -r "calling\|convention\|register\|stack.*slot\|arg_location" "$CANONICAL_OBJ_DIR" 2>/dev/null | wc -l)
    abi_in_ssa=$(grep -r "calling\|convention\|register\|stack.*slot\|arg_location" "$CANONICAL_SSA_DIR" 2>/dev/null | wc -l)
    abi_in_backend=$(grep -r "calling\|convention\|register\|stack.*slot\|arg_location" "$CANONICAL_BACKEND_DIR" 2>/dev/null | wc -l)
    
    echo "  References in obj/: $abi_in_obj"
    echo "  References in ssa/: $abi_in_ssa"
    echo "  References in backend/: $abi_in_backend"
    echo ""
    
    # Check for architecture-specific backends (amd64, arm64, etc.)
    arch_backends=$(find "$CANONICAL_BACKEND_DIR" -maxdepth 1 -type d -name "amd64" -o -name "arm64" -o -name "x86" | wc -l)
    if [ "$arch_backends" -gt 0 ]; then
        echo "  Found architecture-specific backends ($arch_backends)"
        echo "  These typically handle ABI decisions per-architecture"
        abi_authority="BACKEND"
        abi_evidence="Architecture-specific backends (amd64, arm64, etc.) handle ABI"
    else
        # Check for generic ABI handling
        if grep -r "passing\|abi\|ABI" "$CANONICAL_OBJ_DIR" 2>/dev/null | grep -q "func\|struct"; then
            abi_authority="BACKEND"
            abi_evidence="obj/ contains ABI-related functions/structures"
        else
            abi_authority="UNKNOWN"
            abi_evidence="No clear ABI decision authority found"
        fi
    fi
    echo ""
    
    # ========================================
    # 3. Drop Elaboration Authority
    # ========================================
    echo ">>> 3. Drop Elaboration Authority"
    echo ""
    echo "Q: Where are drop calls and ownership cleanup elaborated?"
    echo ""
    
    # Search for drop/cleanup code
    drop_in_obj=$(grep -r "drop\|cleanup\|dtor\|destructor" "$CANONICAL_OBJ_DIR" 2>/dev/null | wc -l)
    drop_in_ssa=$(grep -r "drop\|cleanup\|dtor\|destructor" "$CANONICAL_SSA_DIR" 2>/dev/null | wc -l)
    drop_in_backend=$(grep -r "drop\|cleanup\|dtor\|destructor" "$CANONICAL_BACKEND_DIR" 2>/dev/null | wc -l)
    
    echo "  References in obj/: $drop_in_obj"
    echo "  References in ssa/: $drop_in_ssa"
    echo "  References in backend/: $drop_in_backend"
    echo ""
    
    # Check for ownership-related modules
    ownership_dir="${S_SOURCE_ROOT}/cmd/compile/internal/ownership"
    if [ -d "$ownership_dir" ]; then
        echo "  Found: internal/ownership/ directory"
        if find "$ownership_dir" -name "*.s" | grep -q .; then
            drop_authority="OTHER"
            drop_evidence="ownership/ module handles drop elaboration separately"
        else
            drop_authority="UNKNOWN"
            drop_evidence="ownership/ exists but empty"
        fi
    else
        # Check if drop is in SSA or backend
        if grep -r "drop\|Drop" "$CANONICAL_SSA_DIR" 2>/dev/null | grep -q "func\|struct"; then
            drop_authority="BACKEND"
            drop_evidence="SSA contains drop elaboration logic"
        else
            drop_authority="UNKNOWN"
            drop_evidence="No clear drop elaboration authority"
        fi
    fi
    echo ""
    
    # ========================================
    # 4. Symbol Finalization Authority
    # ========================================
    echo ">>> 4. Symbol Finalization Authority"
    echo ""
    echo "Q: Where are symbols converted to addresses/relocations?"
    echo ""
    
    # Search for symbol resolution
    sym_in_obj=$(grep -r "symbol\|reloc\|address\|patch" "$CANONICAL_OBJ_DIR" 2>/dev/null | wc -l)
    sym_in_backend=$(grep -r "symbol\|reloc\|address\|patch" "$CANONICAL_BACKEND_DIR" 2>/dev/null | wc -l)
    
    echo "  References in obj/: $sym_in_obj"
    echo "  References in backend/: $sym_in_backend"
    echo ""
    
    # Check for linker module
    if [ -d "${S_SOURCE_ROOT}/cmd/compile/internal/link" ]; then
        echo "  Found: internal/link/ directory (post-compilation linking)"
        symbol_authority="OTHER"
        symbol_evidence="link/ module handles symbol finalization (post-backend)"
    else
        # Check in obj/
        if grep -r "symbol\|Symbol" "$CANONICAL_OBJ_DIR" 2>/dev/null | grep -q "func\|struct"; then
            symbol_authority="BACKEND"
            symbol_evidence="obj/ contains symbol handling"
        else
            symbol_authority="UNKNOWN"
            symbol_evidence="No clear symbol finalization authority"
        fi
    fi
    echo ""
    
    # ========================================
    # Decision Completeness Analysis
    # ========================================
    echo "=========================================="
    echo "AUTHORITY MAPPING"
    echo "=========================================="
    echo ""
    echo "type-layout-authority=$layout_authority"
    echo "type-layout-evidence=$layout_evidence"
    echo ""
    echo "abi-decisions-authority=$abi_authority"
    echo "abi-decisions-evidence=$abi_evidence"
    echo ""
    echo "drop-elaboration-authority=$drop_authority"
    echo "drop-elaboration-evidence=$drop_evidence"
    echo ""
    echo "symbol-finalization-authority=$symbol_authority"
    echo "symbol-finalization-evidence=$symbol_evidence"
    echo ""
    
    # ========================================
    # Canonical Lowering Completeness
    # ========================================
    echo "=========================================="
    echo "CANONICAL LOWERING COMPLETENESS"
    echo "=========================================="
    echo ""
    
    # Classify architecture
    backend_count=0
    other_count=0
    missing_count=0
    unknown_count=0
    
    for auth in "$layout_authority" "$abi_authority" "$drop_authority" "$symbol_authority"; do
        if [ "$auth" = "BACKEND" ]; then
            ((backend_count++))
        elif [ "$auth" = "OTHER" ]; then
            ((other_count++))
        elif [ "$auth" = "MISSING" ]; then
            ((missing_count++))
        elif [ "$auth" = "UNKNOWN" ]; then
            ((unknown_count++))
        fi
    done
    
    echo "Authority Distribution:"
    echo "  BACKEND: $backend_count (decisions in backend pass)"
    echo "  OTHER: $other_count (decisions in other modules)"
    echo "  MISSING: $missing_count (decisions not implemented)"
    echo "  UNKNOWN: $unknown_count (unclear location)"
    echo ""
    
    if [ "$missing_count" -eq 0 ] && [ "$unknown_count" -eq 0 ]; then
        completeness="DISTRIBUTED"
        explanation="Decisions exist, scattered across backend/linking stages"
    elif [ "$missing_count" -gt 0 ]; then
        completeness="MISSING"
        explanation="Some decisions are not implemented in canonical"
    else
        completeness="UNCLEAR"
        explanation="Cannot determine implementation status from available evidence"
    fi
    
    echo "canonical-lowering-completeness=$completeness"
    echo "explanation=$explanation"
    echo ""
    
    # ========================================
    # Bootstrap IR Boundary Recommendation
    # ========================================
    echo "=========================================="
    echo "BOOTSTRAP IR BOUNDARY RECOMMENDATION"
    echo "=========================================="
    echo ""
    
    if [ "$completeness" = "DISTRIBUTED" ]; then
        echo "Current State:"
        echo "  Canonical makes all necessary lowering decisions"
        echo "  But they are scattered across backend/linking stages"
        echo "  No explicit LIR (lowered IR) representation exists"
        echo ""
        echo "For Bootstrap IR Path:"
        echo "  Option A: Extract/serialize existing backend lowered state"
        echo "    Pros: No canonical modification needed"
        echo "    Cons: Must hook into backend internals"
        echo ""
        echo "  Option B: Create explicit LIR in canonical"
        echo "    Pros: Clean abstraction, separates semantic from lowering"
        echo "    Cons: Requires canonical refactoring"
        echo ""
        bootstrap_ir_recommendation="SERIALIZATION_OPPORTUNITY"
        
    elif [ "$completeness" = "MISSING" ]; then
        echo "Current State:"
        echo "  Some lowering decisions are not implemented"
        echo "  Canonical would need enhancement before IR bootstrap"
        echo ""
        echo "For Bootstrap IR Path:"
        echo "  Option A: Implement missing decisions in canonical"
        echo "    Pros: Makes canonical complete self-contained"
        echo "    Cons: Development time, may need refactoring"
        echo ""
        echo "  Option B: Use non-IR bootstrap (thin bridge, thin root)"
        echo "    Pros: Avoid canonical modification"
        echo "    Cons: Bootstrap tool more complex"
        echo ""
        bootstrap_ir_recommendation="REQUIRES_CANONICAL_ENHANCEMENT"
        
    else
        echo "Current State:"
        echo "  Implementation status unclear"
        echo "  Need deeper investigation into backend code"
        echo ""
        bootstrap_ir_recommendation="INVESTIGATION_NEEDED"
    fi
    
    echo ""
    echo "bootstrap-ir-boundary-recommendation=$bootstrap_ir_recommendation"
    echo ""
    
    # ========================================
    # Implications for B3.6 Continuation
    # ========================================
    echo "=========================================="
    echo "IMPLICATIONS FOR B3.6 CONTINUATION"
    echo "=========================================="
    echo ""
    
    if [ "$completeness" = "DISTRIBUTED" ]; then
        echo "✓ B3.6.2 Analysis Complete"
        echo ""
        echo "Decisions are made in canonical, but no explicit LIR."
        echo "Next steps:"
        echo "  1. Decide: extract backend state OR create canonical LIR"
        echo "  2. If extract: design serialization layer"
        echo "  3. If LIR: define canonical lowering IR"
        echo "  4. B3.6.3: Design mapping from decision source to bootstrap IR"
        echo ""
        echo "Authority Validation:"
        echo "  ✓ canonical makes all decisions"
        echo "  ✗ adapter still can't be purely structural (no LIR yet)"
        echo ""
        
    elif [ "$completeness" = "MISSING" ]; then
        echo "✗ B3.6.2 Reveals Canonical Gap"
        echo ""
        echo "Some lowering decisions missing from canonical entirely."
        echo "Cannot proceed with IR bootstrap until gap is filled."
        echo ""
        echo "Recommended path:"
        echo "  → Escalate to B4 (Bootstrap Strategy Decision)"
        echo "  → Choose: enhance canonical OR use different root"
        echo "  → Do NOT design adapter for incomplete pipeline"
        echo ""
        
    else
        echo "⚠ B3.6.2 Inconclusive"
        echo ""
        echo "Need deeper code inspection to determine:"
        echo "  - Where decisions actually happen"
        echo "  - Whether backend state is accessible"
        echo "  - Whether canonical is feature-complete"
        echo ""
    fi
    
    echo ""
    echo "=========================================="
    echo "Audit complete. Results saved to:"
    echo "  $AUDIT_OUTPUT"
    echo "=========================================="

} | tee "$AUDIT_OUTPUT"
