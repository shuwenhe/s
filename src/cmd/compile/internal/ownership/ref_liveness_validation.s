package ref_liveness_validation

func validate_straight_last_use(r_live_at_reborrow bool) string {

    if r_live_at_reborrow {
        return "CONFLICT"
    }
    return "ALLOW"
}

func validate_same_place_still_live(r_live_at_reborrow bool) string {

    if r_live_at_reborrow {
        return "CONFLICT"
    }
    return "ALLOW"
}

func validate_branch_all_paths_dead(r_live_at_join bool) string {

    if r_live_at_join {
        return "CONFLICT"
    }
    return "ALLOW"
}

func validate_branch_live_after_join(r_live_at_join bool) string {

    if r_live_at_join {
        return "CONFLICT"
    }
    return "ALLOW"
}

func validate_loop_backedge(r_live_at_exit bool) string {

    if r_live_at_exit {
        return "CONFLICT"
    }
    return "ALLOW"
}

func validate_disjoint_place(places_overlap bool) string {

    if places_overlap {
        return "CONFLICT"
    }
    return "ALLOW"
}
