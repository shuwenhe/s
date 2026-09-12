package compile.internal.ownership

func test_basic_ownership() bool {
    ctx := new_ownership_drop_context()
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    move_stmt := &move_stmt{ source: "x" }
    stmts := []interface{}{ x_decl, move_stmt }
    if !ctx.phase_ownership_analyze(stmts) {
        return false
    }
    if ctx.variableOwners["x"].state != OwnershipState.MOVED {
        return false
    }
    return true
}

func test_use_after_move_error() bool {
    ctx := new_ownership_drop_context()
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    move_stmt := &move_stmt{ source: "x" }
    use_stmt := &move_stmt{ source: "x" }
    
    stmts := []interface{}{ x_decl, move_stmt, use_stmt }
    ok := ctx.phase_ownership_analyze(stmts)
    if ok || len(ctx.errors) == 0 {
        return false
    }
    return true
}

func test_shared_borrow() bool {
    ctx := new_ownership_drop_context()
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    stmts := []interface{}{ x_decl }
    
    if !ctx.phase_ownership_analyze(stmts) {
        return false
    }
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
    if !ctx.phase_borrow_check(borrow_stmts) {
        return false
    }
    return true
}

func test_mutable_borrow_conflict() bool {
    ctx := new_ownership_drop_context()
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    stmts := []interface{}{ x_decl }
    
    if !ctx.phase_ownership_analyze(stmts) {
        return false
    }
    borrow1 := &borrow_stmt{ 
        borrow_var: "r1", 
        source: "x", 
        is_mutable: false,
    }
    borrow2 := &borrow_stmt{ 
        borrow_var: "r2", 
        source: "x", 
        is_mutable: true,
    }
    borrow_stmts := []interface{}{ borrow1, borrow2 }
    ok := ctx.phase_borrow_check(borrow_stmts)
    if ok || len(ctx.errors) == 0 {
        return false
    }
    return true
}

func test_basic_drop_insertion() bool {
    ctx := new_ownership_drop_context()
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    stmts := []interface{}{ x_decl }
    
    ctx.phase_ownership_analyze(stmts)
    ctx.phase_borrow_check(stmts)
    elaborated := ctx.phase_drop_elaboration(stmts)
    if len(elaborated) < 2 {
        return false
    }
    drop_found := false
    for _, stmt := range elaborated {
        if _, is_drop := stmt.(*drop_call); is_drop {
            drop_found = true
            break
        }
    }
    if !drop_found {
        return false
    }
    return true
}

func test_drop_lifo_order() bool {
    ctx := new_ownership_drop_context()
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    y_decl := &decl_stmt{ name: "y", type_name: "File" }
    z_decl := &decl_stmt{ name: "z", type_name: "File" }
    
    stmts := []interface{}{ x_decl, y_decl, z_decl }
    ctx.phase_ownership_analyze(stmts)
    ctx.phase_borrow_check(stmts)
    ctx.build_drop_registry()
    if len(ctx.drop_order) != 3 {
        return false
    }
    if ctx.drop_order[0] != "z" {
        return false
    }
    if ctx.drop_order[1] != "y" {
        return false
    }
    if ctx.drop_order[2] != "x" {
        return false
    }
    return true
}

func test_complete_pipeline_valid() bool {
    ctx := new_ownership_drop_context()
    source_decl := &decl_stmt{ name: "source", type_name: "File" }
    stmts := []interface{}{ source_decl }
    result := ctx.analyze_complete(stmts)
    if !result.success {
        return false
    }
    if len(result.elaborated_stmts) < 1 {
        return false
    }
    found := false
    for _, v := range result.drop_order {
        if v == "source" {
            found = true
            break
        }
    }
    if !found {
        return false
    }
    return true
}

func test_complete_pipeline_invalid() bool {
    ctx := new_ownership_drop_context()
    x_decl := &decl_stmt{ name: "x", type_name: "File" }
    y_move := &move_stmt{ source: "x" }
    z_move := &move_stmt{ source: "x" }
    stmts := []interface{}{ x_decl, y_move, z_move }
    result := ctx.analyze_complete(stmts)
    if result.success {
        return false
    }
    if len(result.errors) == 0 {
        return false
    }
    return true
}

func test_borrow_ends_before_move() bool {
    ctx := new_ownership_drop_context()
    
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
    if len(ctx.errors) > 0 {
        return false
    }
    return true
}

func test_move_while_borrowed_error() bool {
    ctx := new_ownership_drop_context()
    
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
    if ok || len(ctx.errors) == 0 {
        return false
    }
    return true
}

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
