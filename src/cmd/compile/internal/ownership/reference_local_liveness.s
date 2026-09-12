package reference_local_liveness

// reference_local_liveness.s
//
// Phase 1 of NLL (Non-Lexical Lifetimes): Reference Local Liveness
//
// Core goal:
//   loan.active_until = last_use[reference_local]
//   (not scope_end)
//
// Data flow:
//   Use/Def Collection
//        ↓
//   CFG Backward Liveness (may-liveness)
//        ↓
//   Reference Local Live-In/Out
//        ↓
//   Loan Activity Computation
//        ↓
//   Place Borrow Conflict Check (existing)

// ============================================================================
// Data Structures
// ============================================================================

// Reference local occurrence in MIR
struct ref_local_occurrence {
    // Reference local index (from type MIR instruction)
    int ref_local_index
    
    // Basic block where this occurrence happens
    int block_id
    
    // Instruction index within block
    int instr_index
    
    // Type of occurrence
    int occurrence_type  // USE = 1, DEF = 2
}

// Use-Def set for a reference local
struct ref_local_use_def {
    // Reference local index
    int ref_local_index
    
    // All uses: block_id -> set of instr indices
    map[int]vec[int] uses_by_block
    
    // All defs: block_id -> set of instr indices
    map[int]vec[int] defs_by_block
    
    // Associated place (for place overlap checking)
    string place_repr
}

// Liveness information for a reference local at a program point
struct ref_liveness_point {
    // Block and instruction index
    int block_id
    int instr_index
    
    // Is this reference local live?
    bool is_live
}

// Block-level liveness: in/out sets
struct block_liveness {
    int block_id
    
    // live_in[block] = references live at entry
    map[string]bool live_in
    
    // live_out[block] = references live at exit
    map[string]bool live_out
}

// ============================================================================
// Phase 1: Collect Use/Def occurrences
// ============================================================================

func collect_ref_local_use_def(mir_module mir_module) map[int]ref_local_use_def {
    use_def_map := map[int]ref_local_use_def{}
    
    // Iterate over all functions
    for f_idx := 0; f_idx < len(mir_module.functions); f_idx = f_idx + 1 {
        func := mir_module.functions[f_idx]
        
        // Iterate over all basic blocks
        for block_idx := 0; block_idx < len(func.blocks); block_idx = block_idx + 1 {
            block := func.blocks[block_idx]
            
            // Iterate over all instructions in block
            for instr_idx := 0; instr_idx < len(block.statements); instr_idx = instr_idx + 1 {
                stmt := block.statements[instr_idx]
                
                // Collect reference locals from this instruction
                collect_from_statement(stmt, use_def_map, block.block_id, instr_idx)
            }
        }
    }
    
    return use_def_map
}

func collect_from_statement(
    stmt statement,
    use_def_map map[int]ref_local_use_def,
    block_id int,
    instr_idx int,
) {
    // Placeholder: extract reference local uses/defs from statement
    // This would need to:
    // 1. Check if statement references any borrowing
    // 2. Identify the reference local being used/defined
    // 3. Record occurrence type (USE vs DEF)
    
    // For now, empty implementation
    _ = stmt
    _ = use_def_map
    _ = block_id
    _ = instr_idx
}

// ============================================================================
// Phase 2: CFG Backward Liveness Analysis
// ============================================================================

// Standard backward dataflow: may-liveness
//
// live_out[B] = ⋃ live_in[S]  for each successor S
// live_in[B] = use[B] ⋃ (live_out[B] - def[B])

func compute_block_liveness(
    func mir_func,
    use_def use_def_map,
) map[int]block_liveness {
    liveness := map[int]block_liveness{}
    
    // Initialize: empty live_in/live_out for all blocks
    for block_idx := 0; block_idx < len(func.blocks); block_idx = block_idx + 1 {
        block := func.blocks[block_idx]
        bl := block_liveness{
            block_id: block.block_id,
            live_in: map[string]bool{},
            live_out: map[string]bool{},
        }
        liveness[block.block_id] = bl
    }
    
    // Fixed-point iteration
    // Iterate until no changes
    for iteration := 0; iteration < 100; iteration = iteration + 1 {
        changed := false
        
        // Process blocks in reverse post-order (for efficiency)
        // For simplicity, process all blocks
        for block_idx := 0; block_idx < len(func.blocks); block_idx = block_idx + 1 {
            block := func.blocks[block_idx]
            
            // Step 1: live_out[B] = ⋃ live_in[S]
            new_live_out := map[string]bool{}
            for succ_idx := 0; succ_idx < len(block.successors); succ_idx = succ_idx + 1 {
                succ_block_id := block.successors[succ_idx]
                succ_liveness := liveness[succ_block_id]
                
                // Union all successors' live_in into new_live_out
                for ref_name, is_live := range succ_liveness.live_in {
                    if is_live {
                        new_live_out[ref_name] = true
                    }
                }
            }
            
            // Step 2: live_in[B] = use[B] ⋃ (live_out[B] - def[B])
            new_live_in := map[string]bool{}
            
            // Add all uses
            for ref_idx, ud := range use_def {
                _ = ref_idx
                if block_has_use(ud, block.block_id) {
                    new_live_in[ud.place_repr] = true
                }
            }
            
            // Add live_out - def
            for ref_name, is_live := range new_live_out {
                if !block_has_def_for(use_def, ref_name, block.block_id) {
                    new_live_in[ref_name] = is_live
                }
            }
            
            // Check if changed
            old_liveness := liveness[block.block_id]
            if !maps_equal(new_live_in, old_liveness.live_in) || 
               !maps_equal(new_live_out, old_liveness.live_out) {
                changed = true
                old_liveness.live_in = new_live_in
                old_liveness.live_out = new_live_out
                liveness[block.block_id] = old_liveness
            }
        }
        
        if !changed {
            break
        }
    }
    
    return liveness
}

func block_has_use(ud ref_local_use_def, block_id int) bool {
    uses := ud.uses_by_block[block_id]
    return len(uses) > 0
}

func block_has_def_for(
    use_def map[int]ref_local_use_def,
    ref_name string,
    block_id int,
) bool {
    for _, ud := range use_def {
        if ud.place_repr == ref_name {
            defs := ud.defs_by_block[block_id]
            return len(defs) > 0
        }
    }
    return false
}

func maps_equal(m1 map[string]bool, m2 map[string]bool) bool {
    // Placeholder: compare two maps for equality
    // For now, always return false to force iteration
    _ = m1
    _ = m2
    return false
}

// ============================================================================
// Phase 3: Map Liveness to Loan Activity
// ============================================================================

// For each borrow (loan), compute when it's active based on reference liveness
func compute_loan_activity(
    mir_module mir_module,
    use_def map[int]ref_local_use_def,
) map[string]int {
    // loan_id -> last_use_point
    loan_activity := map[string]int{}
    
    // Placeholder: for each loan, find its associated reference local
    // then determine when that reference is no longer live
    
    _ = mir_module
    _ = use_def
    
    return loan_activity
}

// ============================================================================
// Integration: Check Conflicts with Loan Activity
// ============================================================================

// Use existing place borrow conflict checker, but with loan activity instead of scope_end
func check_place_borrow_conflicts_with_liveness(
    mir_module mir_module,
    loan_activity map[string]int,  // loan_id -> last_use_point
) vec[string] {
    conflicts := vec[string]{}
    
    // For each borrow, check if it conflicts with later borrows
    // Use loan_activity instead of assuming loans live to scope_end
    
    // Placeholder: integrate with existing place overlap logic
    _ = mir_module
    _ = loan_activity
    
    return conflicts
}
