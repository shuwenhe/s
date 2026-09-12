package ref_liveness_prototype

// ref_liveness_prototype.s
// 
// Simplified Reference Liveness analyzer for testing
// Works with abstract borrow/use model (not full MIR)
//
// Purpose: Validate liveness semantics before full MIR integration

// ============================================================================
// Simplified Models for Testing
// ============================================================================

// Abstract reference occurrence
struct ref_occurrence {
    string ref_name      // e.g., "r", "r2"
    int block_id         // CFG block
    int point_in_block   // order within block (0, 1, 2, ...)
    string kind          // "borrow", "use", "reborrow"
}

// Simple CFG: blocks and edges
struct simple_cfg {
    vec[simple_block] blocks
}

struct simple_block {
    int id
    string name
    vec[int] successors      // successor block IDs
    vec[ref_occurrence] occurrences
}

// Liveness analysis result
struct liveness_result {
    // ref_name -> bool: is alive at this point?
    map[string]bool live_in_by_block
    map[string]bool live_out_by_block
}

// ============================================================================
// Test Case 1: straight_last_use
// ============================================================================

// borrow r := &x.left
// use(r)              // last use
// reborrow r2 := &x.left
// 
// Expected: ALLOW (loan dead after use)

func build_test1_cfg() simple_cfg {
    cfg := simple_cfg{}
    
    block0 := simple_block{
        id: 0,
        name: "entry",
        successors: vec[int]{},
        occurrences: vec[ref_occurrence]{
            ref_occurrence{ ref_name: "r", block_id: 0, point_in_block: 0, kind: "borrow" },
            ref_occurrence{ ref_name: "r", block_id: 0, point_in_block: 1, kind: "use" },
            ref_occurrence{ ref_name: "r2", block_id: 0, point_in_block: 2, kind: "reborrow" },
        },
    }
    
    cfg.blocks = vec[simple_block]{ block0 }
    return cfg
}

// Analysis for test1:
// block 0 entry:
//   live_out = {} (no successors)
//   use = { r }  (at point 0, borrow creates binding; at point 1, use)
//   def = { r }  (borrow is def)
//   live_in = use ∪ (live_out - def) = {r} ∪ ({} - {r}) = {r}
// 
// Point-by-point liveness:
//   point 0 (borrow r): r becomes live (def creates it)
//   point 1 (use r): r is live
//   point 2 (reborrow r2): r is DEAD (no more uses after point 1)
// 
// Therefore: reborrow should ALLOW

// ============================================================================
// Test Case 3: branch_all_paths_dead
// ============================================================================

// Block structure:
//   block 0: borrow r
//   block 0 -> block 1 (if true)
//   block 0 -> block 2 (if false)
//   block 1: use(r)
//   block 2: (empty)
//   block 1, 2 -> block 3 (join)
//   block 3: reborrow r2
//
// Expected: CONFLICT (may-liveness: union means r is live at join)

func build_test3_cfg() simple_cfg {
    cfg := simple_cfg{}
    
    block0 := simple_block{
        id: 0,
        name: "entry",
        successors: vec[int]{ 1, 2 },
        occurrences: vec[ref_occurrence]{
            ref_occurrence{ ref_name: "r", block_id: 0, point_in_block: 0, kind: "borrow" },
        },
    }
    
    block1 := simple_block{
        id: 1,
        name: "if_true",
        successors: vec[int]{ 3 },
        occurrences: vec[ref_occurrence]{
            ref_occurrence{ ref_name: "r", block_id: 1, point_in_block: 0, kind: "use" },
        },
    }
    
    block2 := simple_block{
        id: 2,
        name: "if_false",
        successors: vec[int]{ 3 },
        occurrences: vec[ref_occurrence]{},  // no use
    }
    
    block3 := simple_block{
        id: 3,
        name: "join",
        successors: vec[int]{},
        occurrences: vec[ref_occurrence]{
            ref_occurrence{ ref_name: "r2", block_id: 3, point_in_block: 0, kind: "reborrow" },
        },
    }
    
    cfg.blocks = vec[simple_block]{ block0, block1, block2, block3 }
    return cfg
}

// Analysis for test3:
// Backward liveness on CFG:
//   block 3: live_out = {} (no succ)
//           use = {} (reborrow is not a use of r)
//           live_in = {} ∪ ({} - {}) = {}
//           BUT: reborrow r2 conflicts with r if r is live
//           Question: is r live at entry to block3?
//
//   block 1: live_out = live_in[3] = {} (from join)
//           use = {r}
//           live_in = {r} ∪ ({} - {}) = {r}
//
//   block 2: live_out = live_in[3] = {}
//           use = {}
//           live_in = {} ∪ ({} - {}) = {}
//
//   block 0: live_out = live_in[1] ∪ live_in[2] = {r} ∪ {} = {r}  ← UNION
//           use = {r} (borrow is def and use site)
//           live_in = {r} ∪ ({r} - {r}) = {r}
//
// At block 3 entry: does r appear in live_out[1] or live_out[2]?
//   live_out[1] = live_in[3] = {}
//   live_out[2] = live_in[3] = {}
//   So r is NOT live at block 3 entry?
//
// Wait, we need to track where r is assigned/bound:
//   r is bound at block 0
//   r is used in block 1
//   At join (block 3): standard may-liveness says r is live if ANY path to join uses r
//   But that's not exactly captured in live_in/live_out...
//
// Actually, the key insight: once r is borrowed in block 0, the loan is active
// The loan remains active until ALL paths that use it have completed
// This is actually about "is the loan still needed?"
//
// Let me reconsider: the liveness we compute is about the *reference variable*
// not about the *place being borrowed*.
// 
// If r := &x means "create a reference to place x.left", then:
// - r is live from borrow to last use
// - x.left remains borrowed while r is live
//
// So at join (block 3):
// - r is not live in block 2 (no use path)
// - r is not live in block 1 after its use
// - r is not live entering block 3
// - Therefore: x.left can be reborrowed!
//
// But user said this should be CONFLICT. Let me re-read their case...
//
// Ah! The issue is: we're doing backward liveness (kill at last use)
// But if one path USES r and another doesn't, at the join we have:
//   May-liveness: "can r be used on ANY execution path?" YES
//   Must-liveness: "is r used on EVERY path?" NO
//
// For borrow checking: we need may-liveness because we must be SAFE on all paths
// So r must be considered live at join if ANY path afterward uses r
//
// But in test case 3, block 3 is the join and it DOESN'T use r
// Only block 1 uses r
//
// So the actual liveness at block 3 should be: live_in[3] determined by:
// - Any uses in block 3? NO
// - Is r alive in successors of block 3? NO successors
// - Therefore: live_in[3] for r = FALSE
//
// This means: reborrow at block 3 should be ALLOWED!
//
// But user's expected result is CONFLICT.
// There's a mismatch in my understanding. Let me think about this differently:
//
// The mismatch might be in how we define "liveness"
// Standard dataflow liveness: "variable is live if its value might be used"
// But for borrows: "loan is active if there are outstanding references"
//
// If r is borrowed in block 0 and used in block 1, then:
// - Block 1: r is live
// - Block 2: r is not live (never used)
// - Block 3 (join): ??? 
//
// One interpretation: r's value persists across blocks, so even in block 2,
// r refers to the same borrowed place. Just because we don't USE it doesn't mean
// the reference is dead.
//
// In that case: liveness should track "reference exists" not "reference is used"
// Then: r is live from block 0 through all blocks until explicitly freed
//
// This suggests: we need different semantics
// - Use: explicit dereference/use of r
// - Live: reference r still exists in scope
//
// For borrow checker: "loan active until reference variable goes out of scope"
// NOT "loan active until last use"
//
// But user said: "loan active = last_use", not scope end
//
// I think the confusion is:
// - Test 1 (straight_last_use): r is used, then reborrow. Loan dies after use. ✓
// - Test 3 (branch_all_paths_dead): naming is misleading!
//   Actually: one path uses r, one doesn't.
//   At the join: r still LIVES (reference variable exists)
//   Because one path HAD a use, r needs to stay alive
//
// So liveness isn't "is r used in this block" but "could r be used later"
//
// At join in test 3:
// - One successor path (block 1) uses r
// - One successor path (block 2) doesn't
// - At join, we conservatively assume r is still live because path 1 uses it
//
// Therefore: reborrow conflicts

// Corrected analysis for test 3:
// Backward liveness: FORWARD through CFG to find paths that USE the reference
// 
// Use[block] = "are there uses of r in this block OR in any successor?"
//
// block 1: use[r] = TRUE (has use(r))
// block 2: use[r] = FALSE
// block 3: use[r] = FALSE
// block 0: use[r] = TRUE (block 1 is successor of block 0)
//
// But standard backward liveness computes this differently...
//
// Maybe the right approach is: forward reachability analysis
// "Starting from borrow site, which blocks can r reach to through uses?"

// ============================================================================
// Simplified Liveness Computation
// ============================================================================

// For now, implement a simple check:
// "is r live at block B?" = "is there any path from B that uses r?"

func compute_simplified_liveness(cfg simple_cfg) {
    // For each reference r and each block B:
    // r is live entering B if:
    //   1. B uses r, OR
    //   2. some successor of B has r live entering it
    
    _ = cfg
}

// ============================================================================
// Entry Point for Testing
// ============================================================================

func analyze_test_case(test_id int) string {
    cfg := simple_cfg{}
    
    if test_id == 1 {
        cfg = build_test1_cfg()
    } else if test_id == 3 {
        cfg = build_test3_cfg()
    }
    
    // TODO: implement actual liveness analysis
    // For now, return placeholder
    
    return "NOT_YET_IMPLEMENTED"
}
