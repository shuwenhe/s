package ref_liveness_tests

// Test 1: straight_last_use
// borrow → use → reborrow
// Expected: ALLOW (loan dead after use)

func test_straight_last_use() {
    mut x mut_int
    x = 0
    
    r := &mut x
    use_ref(r)                      // last use of r
    
    r2 := &mut x                    // should be ALLOWED
    use_ref(r2)
}

// Test 2: same_place_still_live
// borrow → reborrow → later use old ref
// Expected: CONFLICT (old ref r still live at reborrow point)

func test_same_place_still_live() {
    mut x mut_int
    x = 0
    
    r := &mut x
    r2 := &mut x                    // should be CONFLICT
    use_ref(r)                      // r used later
    use_ref(r2)
}

// Test 3: branch_all_paths_dead
// one path uses, one doesn't → after join reborrow
// Expected: CONFLICT (may-liveness union: any path uses r)

func test_branch_all_paths_dead(cond bool) {
    mut x mut_int
    x = 0
    
    r := &mut x
    
    if cond {
        use_ref(r)                  // one path uses r
    }
    // else branch: no use
    
    r2 := &mut x                    // at join: loan STILL active (union)
}

// Test 4: branch_live_after_join  
// borrow → branch with use → join → use AFTER join
// Expected: CONFLICT (second use keeps loan active)

func test_branch_live_after_join(cond bool) {
    mut x mut_int
    x = 0
    
    r := &mut x
    
    if cond {
        use_ref(r)
    }
    
    use_ref(r)                      // use AFTER join point
    r2 := &mut x                    // CONFLICT: loan active
}

// Test 5: loop_backedge
// borrow → loop with use → after loop reborrow
// Expected: CONFLICT (backedge propagates liveness)

func test_loop_backedge() {
    mut x mut_int
    x = 0
    
    r := &mut x
    
    mut i int
    i = 0
    loop {
        if i > 10 {
            break
        }
        use_ref(r)
        i = i + 1
    }
    
    r2 := &mut x                    // CONFLICT: loan active due to loop
}

// Test 6: disjoint_place
// borrow x.left → reborrow x.right
// Expected: ALLOW (disjoint places)

struct record {
    mut left mut_int
    mut right mut_int
}

func test_disjoint_place() {
    mut rec record
    rec.left = 0
    rec.right = 0
    
    r := &mut rec.left
    use_ref(r)                      // use r
    
    r2 := &mut rec.right            // ALLOW: different field
    use_ref(r2)
}

// Dummy function to model "use"
func use_ref(r &mut int) {
    v := *r
    _ = v
}
