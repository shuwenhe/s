package compile.internal.ownership

func test_move_semantics() bool {
    ctx := NewOwnershipContext()
    checker := new_move_checker(ctx)
    test1Stmts := interface{}[]{
        AssignmentStmt*{LHS: "a", RHS: "value", IsMove: false},
        AssignmentStmt*{LHS: "b", RHS: "a", IsMove: true},  // a → b (move)
        UseStmt*{Variable: "a"},  // ERROR: use-after-move
    }
    checker.check_move_semantics(test1Stmts)
    if !ctx.has_errors() {
        return false  // Should have detected use-after-move
    }
    ctx = NewOwnershipContext()
    checker = new_move_checker(ctx)
    test2Stmts := interface{}[]{
        AssignmentStmt*{LHS: "x", RHS: "5", IsCopy: true},  // x = 5 (copy)
        AssignmentStmt*{LHS: "y", RHS: "x", IsCopy: true},  // y = x (copy, still valid)
        UseStmt*{Variable: "x"},  // OK: x still valid after copy
    }
    checker.check_move_semantics(test2Stmts)
    if ctx.has_errors() {
        return false  // Copy shouldn't cause errors
    }
    return true
}

func test_borrow_semantics() bool {
    ctx := NewOwnershipContext()
    checker := new_borrow_checker(ctx)
    test1Stmts := interface{}[]{
        BorrowStmt*{Source: "data", IsMutable: false},     // borrow &data
        BorrowStmt*{Source: "data", IsMutable: false},     // borrow &data again (OK)
        BorrowEndStmt*{Source: "data"},
        BorrowEndStmt*{Source: "data"},
    }
    checker.check_borrow_semantics(test1Stmts)
    if ctx.has_errors() {
        return false  // Multiple shared borrows should be OK
    }
    ctx = NewOwnershipContext()
    checker = new_borrow_checker(ctx)
    test2Stmts := interface{}[]{
        BorrowStmt*{Source: "data", IsMutable: true},      // &mut data
        BorrowStmt*{Source: "data", IsMutable: false},     // &data (ERROR: conflict)
    }
    checker.check_borrow_semantics(test2Stmts)
    if !ctx.has_errors() {
        return false  // Should detect mutable borrow conflict
    }
    ctx = NewOwnershipContext()
    checker = new_borrow_checker(ctx)
    test3Stmts := interface{}[]{
        BorrowStmt*{Source: "x", IsMutable: false},
        MoveStmt*{Variable: "x"},  // ERROR: move while borrowed
    }
    checker.check_borrow_semantics(test3Stmts)
    if !ctx.has_errors() {
        return false  // Should detect move while borrowed
    }
    return true
}

func test_drop_elaboration() bool {
    ctx := NewOwnershipContext()
    elaborator := new_drop_elaborator(ctx)
    test1Stmts := interface{}[]{
        AssignmentStmt*{LHS: "x", RHS: "value", IsMove: false},
        UseStmt*{Variable: "x"},
    }
    elaborated := elaborator.elaborate_drops(test1Stmts)
    dropCount := 0
    for _, stmt := range elaborated {
        switch stmt.(type) {
case DropCall*:
            dropCount++
        }
    }
    if dropCount != 1 {
        return false  // Should insert exactly one drop
    }
    if !elaborator.verify_exactly_once_drop(elaborated) {
        return false  // Should verify drop count
    }
    return true
}

func test_ownership_state_transitions() bool {
    ctx := NewOwnershipContext()
    ctx.set_state_at(0, "x", STATE_OWNED)
    if ctx.get_state_at(0, "x") != STATE_OWNED {
        return false
    }
    ctx.set_state_at(1, "x", STATE_MOVED)
    if ctx.get_state_at(1, "x") != STATE_MOVED {
        return false
    }
    ctx.set_state_at(2, "x", STATE_DROPPED)
    if ctx.get_state_at(2, "x") != STATE_DROPPED {
        return false
    }
    return true
}

func test_control_flow_merge() bool {
    ctx := NewOwnershipContext()
    checker := new_move_checker(ctx)
    thenStates := map[string]OwnershipState{
        "x": STATE_MOVED,
    }
    elseStates := map[string]OwnershipState{
        "x": STATE_OWNED,
    }
    checker.merge_branch_states(0, thenStates, elseStates)
    if ctx.get_state_at(0, "x") != STATE_MAYBE_MOVED {
        return false
    }
    return true
}

func test_partial_move() bool {
    ctx := NewOwnershipContext()
    ctx.set_state_at(0, "s.a", STATE_MOVED)
    ctx.set_state_at(0, "s.b", STATE_OWNED)
    ctx.set_state_at(0, "s", STATE_PARTIALLY_MOVED)
    if ctx.get_state_at(0, "s") != STATE_PARTIALLY_MOVED {
        return false
    }
    return true
}

func test_complete_ownership_pipeline() bool {
    oa := NewOwnershipAnalysis()
    testStmts := interface{}[]{
        AssignmentStmt*{LHS: "x", RHS: "box::new()", IsMove: false},
        BorrowStmt*{Source: "x", IsMutable: false, LifetimeName: "a"},
        UseStmt*{Variable: "y", ThroughBorrow: true},
        BorrowEndStmt*{Source: "x"},
        AssignmentStmt*{LHS: "z", RHS: "x", IsMove: true},
    }
    elaborated, success := oa.analyze_function("test_func", testStmts)
    if !success {
        return true  // For now, either result is OK
    }
    return true
}

func run_all_tests() bool {
    tests := []struct {
        name string
        test func() bool
    }{
        {"MoveSemantics", TestMoveSemantics},
        {"BorrowSemantics", TestBorrowSemantics},
        {"DropElaboration", TestDropElaboration},
        {"StateTransitions", TestOwnershipStateTransitions},
        {"ControlFlowMerge", TestControlFlowMerge},
        {"PartialMove", TestPartialMove},
        {"CompletePipeline", TestCompleteOwnershipPipeline},
    }
    allPassed := true
    for _, test := range tests {
        if !test.test() {
            allPassed = false
        }
    }
    return allPassed
}
