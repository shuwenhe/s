// Expected liveness and conflict results for Reference Liveness tests
// Format: test_name -> [liveness_analysis] -> [conflicts]

package ref_liveness_expected

// Test 1: straight_last_use
// r live in: [BB0: borrow line]
// r live out: [BB0: after use]
// Expected: NO CONFLICT at reborrow
const test1_expected_result = "ALLOW"

// Test 2: same_place_still_live  
// r live in: [BB0: borrow line through use line]
// At reborrow: r STILL LIVE
// Expected: CONFLICT
const test2_expected_result = "CONFLICT"

// Test 3: branch_all_paths_dead
// r borrow at BB0
// BB0 -> BB1 (if true) / BB2 (else)
// BB1: use(r)
// BB2: no use
// BB1 join BB3, BB2 join BB3
// At BB3 (join): live_in[BB3] = live_in[BB1] ⋃ live_in[BB2]
//                             = {r} ⋃ {r}  (may-liveness: any path uses)
//                             = {r}
// Expected: CONFLICT at reborrow in BB3
const test3_expected_result = "CONFLICT"

// Test 4: branch_live_after_join
// BB0: borrow r
// BB0 -> BB1 (if) / BB2 (else)
// BB1: use(r)
// BB1, BB2 join BB3
// BB3: use(r) AFTER join
// At reborrow in BB3: r LIVE (due to post-join use)
// Expected: CONFLICT
const test4_expected_result = "CONFLICT"

// Test 5: loop_backedge
// BB0: borrow r
// BB0 -> BB1 (loop header)
// BB1 -> BB2 (loop body: use r)
// BB2 -> BB1 (backedge) or BB3 (exit)
// Backedge propagates: r live in BB1, BB2
// At BB3 (exit): liveness from loop still present
// Expected: CONFLICT at reborrow
const test5_expected_result = "CONFLICT"

// Test 6: disjoint_place
// r = &mut x.left
// r2 = &mut x.right
// Even if r LIVE, places don't overlap
// Expected: ALLOW
const test6_expected_result = "ALLOW"

// Summary of MIR conflict checks
// [straight_last_use]          -> ALLOW   ✓
// [same_place_still_live]      -> CONFLICT ✓
// [branch_all_paths_dead]      -> CONFLICT ✓
// [branch_live_after_join]     -> CONFLICT ✓
// [loop_backedge]              -> CONFLICT ✓
// [disjoint_place]             -> ALLOW    ✓
