package ref_liveness_tests

func test_straight_last_use() {
    mut x mut_int
    x = 0

    r := &mut x
    use_ref(r)

    r2 := &mut x
    use_ref(r2)
}

func test_same_place_still_live() {
    mut x mut_int
    x = 0

    r := &mut x
    r2 := &mut x
    use_ref(r)
    use_ref(r2)
}

func test_branch_all_paths_dead(cond bool) {
    mut x mut_int
    x = 0

    r := &mut x

    if cond {
        use_ref(r)
    }

    r2 := &mut x
}

func test_branch_live_after_join(cond bool) {
    mut x mut_int
    x = 0

    r := &mut x

    if cond {
        use_ref(r)
    }

    use_ref(r)
    r2 := &mut x
}

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

    r2 := &mut x
}

struct record {
    mut left mut_int
    mut right mut_int
}

func test_disjoint_place() {
    mut rec record
    rec.left = 0
    rec.right = 0

    r := &mut rec.left
    use_ref(r)

    r2 := &mut rec.right
    use_ref(r2)
}

func use_ref(r &mut int) {
    v := *r
    _ = v
}
