package ref_liveness_validation

// ref_liveness_validation.s
// 
// Validation logic for reference liveness results
// To be integrated with real MIR analysis later

// Test validation: does the liveness analysis match expected behavior?

func validate_straight_last_use(r_live_at_reborrow bool) string {
    // Test 1: r should be DEAD at reborrow (after last-use)
    if r_live_at_reborrow {
        return "CONFLICT"
    }
    return "ALLOW"
}

func validate_same_place_still_live(r_live_at_reborrow bool) string {
    // Test 2: r should be LIVE at reborrow (used later)
    if r_live_at_reborrow {
        return "CONFLICT"
    }
    return "ALLOW"
}

func validate_branch_all_paths_dead(r_live_at_join bool) string {
    // Test 3: r should be DEAD at join (no use after join)
    if r_live_at_join {
        return "CONFLICT"
    }
    return "ALLOW"
}

func validate_branch_live_after_join(r_live_at_join bool) string {
    // Test 4: r should be LIVE at join (use after join)
    if r_live_at_join {
        return "CONFLICT"
    }
    return "ALLOW"
}

func validate_loop_backedge(r_live_at_exit bool) string {
    // Test 5: r should be LIVE at exit (backedge propagates)
    if r_live_at_exit {
        return "CONFLICT"
    }
    return "ALLOW"
}

func validate_disjoint_place(places_overlap bool) string {
    // Test 6: different places - overlap check, not liveness
    if places_overlap {
        return "CONFLICT"
    }
    return "ALLOW"
}
