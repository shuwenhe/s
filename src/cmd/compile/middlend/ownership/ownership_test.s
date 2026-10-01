package compile.internal.ownership

func test_move_semantics() bool {
    ctx := new_ownership_context()
    checker := new_move_checker(ctx)
    test1_stmts := interface{}[]{
        assignment_stmt*{lhs: "a", rhs: "value", is_move: false},
        assignment_stmt*{lhs: "b", rhs: "a", is_move: true},
        use_stmt*{variable: "a"},
    }
    checker.check_move_semantics(test1_stmts)
    if !ctx.has_errors() {
        return false
    }
    ctx = new_ownership_context()
    checker = new_move_checker(ctx)
    test2_stmts := interface{}[]{
        assignment_stmt*{lhs: "x", rhs: "5", is_copy: true},
        assignment_stmt*{lhs: "y", rhs: "x", is_copy: true},
        use_stmt*{variable: "x"},
    }
    checker.check_move_semantics(test2_stmts)
    if ctx.has_errors() {
        return false
    }
    return true
}

func test_borrow_semantics() bool {
    ctx := new_ownership_context()
    checker := new_borrow_checker(ctx)
    test1_stmts := interface{}[]{
        borrow_stmt*{source: "data", is_mutable: false},
        borrow_stmt*{source: "data", is_mutable: false},
        borrow_end_stmt*{source: "data"},
        borrow_end_stmt*{source: "data"},
    }
    checker.check_borrow_semantics(test1_stmts)
    if ctx.has_errors() {
        return false
    }
    ctx = new_ownership_context()
    checker = new_borrow_checker(ctx)
    test2_stmts := interface{}[]{
        borrow_stmt*{source: "data", is_mutable: true},
        borrow_stmt*{source: "data", is_mutable: false},
    }
    checker.check_borrow_semantics(test2_stmts)
    if !ctx.has_errors() {
        return false
    }
    ctx = new_ownership_context()
    checker = new_borrow_checker(ctx)
    test3_stmts := interface{}[]{
        borrow_stmt*{source: "x", is_mutable: false},
        move_stmt*{variable: "x"},
    }
    checker.check_borrow_semantics(test3_stmts)
    if !ctx.has_errors() {
        return false
    }
    return true
}

func test_drop_elaboration() bool {
    ctx := new_ownership_context()
    elaborator := new_drop_elaborator(ctx)
    test1_stmts := interface{}[]{
        assignment_stmt*{lhs: "x", rhs: "value", is_move: false},
        use_stmt*{variable: "x"},
    }
    elaborated := elaborator.elaborate_drops(test1_stmts)
    drop_count := 0
    for _, stmt := range elaborated {
        switch stmt.(type) {
case drop_call*:
            drop_count++
        }
    }
    if drop_count != 1 {
        return false
    }
    if !elaborator.verify_exactly_once_drop(elaborated) {
        return false
    }
    return true
}

func test_ownership_state_transitions() bool {
    ctx := new_ownership_context()
    ctx.set_state_at(0, "x", state_owned)
    if ctx.get_state_at(0, "x") != state_owned {
        return false
    }
    ctx.set_state_at(1, "x", state_moved)
    if ctx.get_state_at(1, "x") != state_moved {
        return false
    }
    ctx.set_state_at(2, "x", state_dropped)
    if ctx.get_state_at(2, "x") != state_dropped {
        return false
    }
    return true
}

func test_control_flow_merge() bool {
    ctx := new_ownership_context()
    checker := new_move_checker(ctx)
    then_states := map[string]ownership_state{
        "x": state_moved,
    }
    else_states := map[string]ownership_state{
        "x": state_owned,
    }
    checker.merge_branch_states(0, then_states, else_states)
    if ctx.get_state_at(0, "x") != state_maybe_moved {
        return false
    }
    return true
}

func test_partial_move() bool {
    ctx := new_ownership_context()
    ctx.set_state_at(0, "s.a", state_moved)
    ctx.set_state_at(0, "s.b", state_owned)
    ctx.set_state_at(0, "s", state_partially_moved)
    if ctx.get_state_at(0, "s") != state_partially_moved {
        return false
    }
    return true
}

func test_complete_ownership_pipeline() bool {
    oa := new_ownership_analysis()
    test_stmts := interface{}[]{
        assignment_stmt*{lhs: "x", rhs: "box::new()", is_move: false},
        borrow_stmt*{source: "x", is_mutable: false, lifetime_name: "a"},
        use_stmt*{variable: "y", through_borrow: true},
        borrow_end_stmt*{source: "x"},
        assignment_stmt*{lhs: "z", rhs: "x", is_move: true},
    }
    elaborated, success := oa.analyze_function("test_func", test_stmts)
    if !success {
        return true
    }
    return true
}

func run_all_tests() bool {
    tests := []struct {
        name string
        test func() bool
    }{
        {"move_semantics", test_movesemantics},
        {"borrow_semantics", test_borrowsemantics},
        {"DropElaboration", test_dropelaboration},
        {"state_transitions", test_ownershipstatetransitions},
        {"control_flow_merge", test_controlflowmerge},
        {"partial_move", test_partialmove},
        {"CompletePipeline", test_completeownershippipeline},
    }
    all_passed := true
    for _, test := range tests {
        if !test.test() {
            all_passed = false
        }
    }
    return all_passed
}
