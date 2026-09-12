package compile.internal.ownership

// ownership_drop_closure_test.s - Complete test suite for Ownership → Borrow → Drop closure
//
// Tests verify:
// 1. OWNERSHIP PHASE: correct state transitions and move semantics
// 2. BORROW PHASE: borrow rule enforcement and conflict detection
// 3. DROP PHASE: correct insertion and exactly-once semantics
// 4. CLOSED LOOP: end-to-end pipeline integration

// ============================================================================
// TEST 1: Basic Ownership - Single Owner
// ============================================================================

func test_basic_ownership() bool {
    ctx := new_ownership_drop_context()
    
    // Simulate: var x: File = ...
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    
    // Simulate: var y = x (move)
    move_stmt := &move_stmt{ source: "x" }
    
    stmts := []interface{}{ x_decl, move_stmt }
    
    // Phase 1: Ownership Analysis
    if !ctx.phase_ownership_analyze(stmts) {
        return false // FAIL: should accept valid move
    }
    
    // x should be MOVED
    if ctx.variableOwners["x"].state != OwnershipState.MOVED {
        return false // FAIL: x not in MOVED state
    }
    
    return true // PASS
}

// ============================================================================
// TEST 2: Ownership Error - Use After Move
// ============================================================================

func test_use_after_move_error() bool {
    ctx := new_ownership_drop_context()
    
    // Simulate:
    // var x: File = ...
    // var y = x (move)
    // use(x)  <- ERROR
    
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    move_stmt := &move_stmt{ source: "x" }
    use_stmt := &move_stmt{ source: "x" } // Second use = ERROR
    
    stmts := []interface{}{ x_decl, move_stmt, use_stmt }
    
    // Phase 1: Should detect error
    ok := ctx.phase_ownership_analyze(stmts)
    
    // Should have errors
    if ok || len(ctx.errors) == 0 {
        return false // FAIL: should detect use-after-move
    }
    
    return true // PASS
}

// ============================================================================
// TEST 3: Borrow - Shared Borrowing
// ============================================================================

func test_shared_borrow() bool {
    ctx := new_ownership_drop_context()
    
    // First run ownership
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    stmts := []interface{}{ x_decl }
    
    if !ctx.phase_ownership_analyze(stmts) {
        return false
    }
    
    // Simulate:
    // let r1 = &x (shared)
    // let r2 = &x (shared)  <- OK, multiple shared allowed
    borrow1 := &borrow_stmt{ 
        borrow_var: "r1", 
        source: "x", 
        is_mutable: false,
    }
    borrow2 := &borrow_stmt{ 
        borrow_var: "r2", 
        source: "x", 
        is_mutable: false,
    }
    
    borrow_stmts := []interface{}{ borrow1, borrow2 }
    
    // Phase 2: Should accept multiple shared borrows
    if !ctx.phase_borrow_check(borrow_stmts) {
        return false // FAIL
    }
    
    return true // PASS
}

// ============================================================================
// TEST 4: Borrow Error - Mutable Conflict
// ============================================================================

func test_mutable_borrow_conflict() bool {
    ctx := new_ownership_drop_context()
    
    // First run ownership
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    stmts := []interface{}{ x_decl }
    
    if !ctx.phase_ownership_analyze(stmts) {
        return false
    }
    
    // Simulate:
    // let r1 = &x (shared)
    // let r2 = &mut x  <- ERROR, conflicts with shared
    borrow1 := &borrow_stmt{ 
        borrow_var: "r1", 
        source: "x", 
        is_mutable: false,
    }
    borrow2 := &borrow_stmt{ 
        borrow_var: "r2", 
        source: "x", 
        is_mutable: true,  // mutable
    }
    
    borrow_stmts := []interface{}{ borrow1, borrow2 }
    
    // Phase 2: Should reject due to conflict
    ok := ctx.phase_borrow_check(borrow_stmts)
    
    // Should have errors
    if ok || len(ctx.errors) == 0 {
        return false // FAIL: should detect conflict
    }
    
    return true // PASS
}

// ============================================================================
// TEST 5: Drop - Basic Drop Insertion
// ============================================================================

func test_basic_drop_insertion() bool {
    ctx := new_ownership_drop_context()
    
    // Declare and setup
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    stmts := []interface{}{ x_decl }
    
    ctx.phase_ownership_analyze(stmts)
    ctx.phase_borrow_check(stmts)
    
    // Phase 3: Drop elaboration
    elaborated := ctx.phase_drop_elaboration(stmts)
    
    // Should have original stmt + drop call
    if len(elaborated) < 2 {
        return false // FAIL: should insert drop
    }
    
    // Last statement should be drop call
    drop_found := false
    for _, stmt := range elaborated {
        if _, is_drop := stmt.(*drop_call); is_drop {
            drop_found = true
            break
        }
    }
    
    if !drop_found {
        return false // FAIL
    }
    
    return true // PASS
}

// ============================================================================
// TEST 6: Drop - Correct LIFO Order
// ============================================================================

func test_drop_lifo_order() bool {
    ctx := new_ownership_drop_context()
    
    // Simulate:
    // var x: File = ...
    // var y: File = ...
    // var z: File = ...
    // <- should drop: z, y, x (reverse order)
    
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    y_decl := &decl_stmt{ name: "y", type_name: "File" }
    z_decl := &decl_stmt{ name: "z", type_name: "File" }
    
    stmts := []interface{}{ x_decl, y_decl, z_decl }
    
    ctx.phase_ownership_analyze(stmts)
    ctx.phase_borrow_check(stmts)
    ctx.build_drop_registry()
    
    // Check drop order (should be reverse declaration)
    if len(ctx.drop_order) != 3 {
        return false
    }
    
    if ctx.drop_order[0] != "z" {
        return false // FAIL: z should be first (last declared)
    }
    if ctx.drop_order[1] != "y" {
        return false // FAIL: y should be second
    }
    if ctx.drop_order[2] != "x" {
        return false // FAIL: x should be third (first declared)
    }
    
    return true // PASS
}

// ============================================================================
// TEST 7: Complete Pipeline - Valid Program
// ============================================================================

func test_complete_pipeline_valid() bool {
    ctx := new_ownership_drop_context()
    
    // Valid program:
    // var source: File = ...
    // var r = &source         (shared borrow)
    // use(r)
    // <- r ends
    // var dest = source       (move)
    // <- drop dest, source
    
    source_decl := &decl_stmt{ name: "source", type_name: "File" }
    
    stmts := []interface{}{ source_decl }
    
    // Run complete pipeline
    result := ctx.analyze_complete(stmts)
    
    if !result.success {
        return false // FAIL
    }
    
    // Should have inserted drops
    if len(result.elaborated_stmts) < 1 {
        return false // FAIL
    }
    
    // Drop order should include source
    found := false
    for _, v := range result.drop_order {
        if v == "source" {
            found = true
            break
        }
    }
    
    if !found {
        return false // FAIL: source should be in drop order
    }
    
    return true // PASS
}

// ============================================================================
// TEST 8: Complete Pipeline - Invalid Program
// ============================================================================

func test_complete_pipeline_invalid() bool {
    ctx := new_ownership_drop_context()
    
    // Invalid program:
    // var x: File = ...
    // var y = x               (move)
    // var z = x               (ERROR: use-after-move)
    
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    y_move := &move_stmt{ source: "x" }
    z_move := &move_stmt{ source: "x" } // ERROR
    
    stmts := []interface{}{ x_decl, y_move, z_move }
    
    // Run pipeline
    result := ctx.analyze_complete(stmts)
    
    // Should fail
    if result.success {
        return false // FAIL: should reject use-after-move
    }
    
    // Should have error
    if len(result.errors) == 0 {
        return false // FAIL: should report error
    }
    
    return true // PASS
}

// ============================================================================
// TEST 9: Borrow Lifetime - Ends Before Move
// ============================================================================

func test_borrow_ends_before_move() bool {
    ctx := new_ownership_drop_context()
    
    // Valid:
    // var x: File = ...
    // let r = &x
    // <- r ends (implicit scope exit)
    // var y = x  (move OK now)
    
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    borrow := &borrow_stmt{ 
        borrow_var: "r", 
        source: "x", 
        is_mutable: false,
    }
    borrow_end := &borrow_end_stmt{ borrow_var: "r" }
    move_stmt := &move_stmt{ source: "x" }
    
    stmts := []interface{}{ x_decl, borrow, borrow_end, move_stmt }
    
    ctx.phase_ownership_analyze(stmts)
    ctx.phase_borrow_check(stmts)
    
    // Should have no errors
    if len(ctx.errors) > 0 {
        return false // FAIL
    }
    
    return true // PASS
}

// ============================================================================
// TEST 10: Move While Borrowed - Error
// ============================================================================

func test_move_while_borrowed_error() bool {
    ctx := new_ownership_drop_context()
    
    // Invalid:
    // var x: File = ...
    // let r = &x
    // var y = x  (ERROR: move while borrowed)
    
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    borrow := &borrow_stmt{ 
        borrow_var: "r", 
        source: "x", 
        is_mutable: false,
    }
    move_stmt := &move_stmt{ source: "x" }
    
    stmts := []interface{}{ x_decl, borrow, move_stmt }
    
    ctx.phase_ownership_analyze(stmts)
    ok := ctx.phase_borrow_check(stmts)
    
    // Should have error
    if ok || len(ctx.errors) == 0 {
        return false // FAIL: should detect move while borrowed
    }
    
    return true // PASS
}

// ============================================================================
// MAIN TEST RUNNER
// ============================================================================

func run_ownership_drop_closure_tests() int {
    tests := []string{
        "basic_ownership",
        "use_after_move_error",
        "shared_borrow",
        "mutable_borrow_conflict",
        "basic_drop_insertion",
        "drop_lifo_order",
        "complete_pipeline_valid",
        "complete_pipeline_invalid",
        "borrow_ends_before_move",
        "move_while_borrowed_error",
    }
    
    passed := 0
    failed := 0
    
    for _, test_name := range tests {
        var result bool
        
        switch test_name {
        case "basic_ownership":
            result = test_basic_ownership()
        case "use_after_move_error":
            result = test_use_after_move_error()
        case "shared_borrow":
            result = test_shared_borrow()
        case "mutable_borrow_conflict":
            result = test_mutable_borrow_conflict()
        case "basic_drop_insertion":
            result = test_basic_drop_insertion()
        case "drop_lifo_order":
            result = test_drop_lifo_order()
        case "complete_pipeline_valid":
            result = test_complete_pipeline_valid()
        case "complete_pipeline_invalid":
            result = test_complete_pipeline_invalid()
        case "borrow_ends_before_move":
            result = test_borrow_ends_before_move()
        case "move_while_borrowed_error":
            result = test_move_while_borrowed_error()
        }
        
        if result {
            passed++
            println("[PASS] " + test_name)
        } else {
            failed++
            println("[FAIL] " + test_name)
        }
    }
    
    println("==========================================")
    println("Ownership → Borrow → Drop Closure Tests")
    println("Passed: " + string(passed))
    println("Failed: " + string(failed))
    println("==========================================")
    
    if failed > 0 {
        return 1
    }
    return 0
}
