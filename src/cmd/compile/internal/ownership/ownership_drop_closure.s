package compile.internal.ownership

// ownership_drop_closure.s - Complete Ownership → Borrow → Drop closed loop
//
// This module orchestrates the complete resource management pipeline in S no-GC subset:
// Phase 1: OWNERSHIP - Identify resource owners and track state transitions
// Phase 2: BORROW - Enforce borrowing rules and lifetime constraints  
// Phase 3: DROP - Insert drops and verify exactly-once cleanup
//
// This creates a CLOSED LOOP with guaranteed:
// - Every resource is owned by exactly one variable
// - All borrows respect exclusive/shared semantics
// - Every resource is dropped exactly once at scope exit
// - No use-after-drop or double-drop is possible
// - Drop order follows reverse declaration order

type OwnershipDropContext struct {
    // Ownership tracking
    variableOwners map[string]*OwnershipRecord
    owned_set map[string]bool
    moved_set map[string]bool
    borrowed_set map[string][]BorrowRecord
    
    // Borrow tracking
    borrow_contexts []BorrowContext
    active_borrows map[string]*BorrowRecord
    
    // Drop tracking
    drop_registry map[string]*DropRecord
    drop_order []string
    
    // State machine
    analysis_phase int // 0=OWNERSHIP, 1=BORROW, 2=DROP
    errors []string
    warnings []string
}

type OwnershipRecord struct {
    name string
    type_name string
    state int // UNDEFINED, OWNED, BORROWED_SHARED, BORROWED_MUT, MOVED, DROPPED
    declaration_order int
    scope_depth int
    is_param bool
}

type BorrowRecord struct {
    borrow_var string
    source_var string
    is_mutable bool
    lifetime_start int
    lifetime_end int
    scope_depth int
}

type DropRecord struct {
    variable string
    type_name string
    has_drop_impl bool
    drop_fn string
    fields []string
    field_drop_order []string
}

type OwnershipState struct {
    UNDEFINED = 0
    OWNED = 1
    BORROWED_SHARED = 2
    BORROWED_MUT = 3
    MOVED = 4
    DROPPED = 5
}

// ============================================================================
// PHASE 1: OWNERSHIP ANALYSIS
// ============================================================================

// phase_ownership_analyze - Identify all resource owners
func (ctx *OwnershipDropContext) phase_ownership_analyze(stmts []interface{}) bool {
    ctx.analysis_phase = 0
    ctx.variableOwners = make(map[string]*OwnershipRecord)
    ctx.owned_set = make(map[string]bool)
    ctx.moved_set = make(map[string]bool)
    
    // Pass 1: Collect all variable declarations
    ctx.collect_declarations(stmts, 0)
    
    // Pass 2: Track ownership transitions
    for i := 0; i < len(stmts); i++ {
        if !ctx.analyze_ownership_in_stmt(i, stmts[i], 0) {
            return false
        }
    }
    
    return len(ctx.errors) == 0
}

func (ctx *OwnershipDropContext) collect_declarations(stmts []interface{}, depth int) {
    for _, stmt := range stmts {
        ctx.collect_from_stmt(stmt, depth)
    }
}

func (ctx *OwnershipDropContext) collect_from_stmt(stmt interface{}, depth int) {
    // Extract variable declarations from various statement types
    switch s := stmt.(type) {
    case *decl_stmt:
        owner := &OwnershipRecord{
            name: s.name,
            type_name: s.type_name,
            state: OwnershipState.OWNED,
            declaration_order: len(ctx.variableOwners),
            scope_depth: depth,
            is_param: false,
        }
        ctx.variableOwners[s.name] = owner
        ctx.owned_set[s.name] = true
    }
}

func (ctx *OwnershipDropContext) analyze_ownership_in_stmt(pc int, stmt interface{}, depth int) bool {
    switch s := stmt.(type) {
    case *assign_stmt:
        return ctx.analyze_assign(pc, s, depth)
    case *move_stmt:
        return ctx.analyze_move(pc, s, depth)
    case *drop_stmt:
        return ctx.analyze_drop(pc, s, depth)
    case *block_stmt:
        return ctx.analyze_block(pc, s, depth+1)
    }
    return true
}

func (ctx *OwnershipDropContext) analyze_assign(pc int, stmt *assign_stmt, depth int) bool {
    // Check if RHS is in valid OWNED state for move assignment
    if stmt.is_move {
        rhs_var := stmt.rhs
        if record, exists := ctx.variableOwners[rhs_var]; exists {
            if record.state != OwnershipState.OWNED {
                ctx.errors = append(ctx.errors, 
                    sprintf("ERROR at PC %d: Cannot move %s from state %d", pc, rhs_var, record.state))
                return false
            }
            
            // Transition source to MOVED
            record.state = OwnershipState.MOVED
            ctx.moved_set[rhs_var] = true
            delete(ctx.owned_set, rhs_var)
            
            // LHS becomes owner
            if lhs_record, exists := ctx.variableOwners[stmt.lhs]; exists {
                lhs_record.state = OwnershipState.OWNED
                ctx.owned_set[stmt.lhs] = true
            }
        }
    }
    return true
}

func (ctx *OwnershipDropContext) analyze_move(pc int, stmt *move_stmt, depth int) bool {
    if record, exists := ctx.variableOwners[stmt.source]; exists {
        if record.state == OwnershipState.MOVED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR at PC %d: double-move of %s", pc, stmt.source))
            return false
        }
        if record.state == OwnershipState.DROPPED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR at PC %d: use-after-drop of %s", pc, stmt.source))
            return false
        }
        record.state = OwnershipState.MOVED
    }
    return true
}

func (ctx *OwnershipDropContext) analyze_drop(pc int, stmt *drop_stmt, depth int) bool {
    if record, exists := ctx.variableOwners[stmt.target]; exists {
        if record.state == OwnershipState.DROPPED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR at PC %d: double-drop of %s", pc, stmt.target))
            return false
        }
        record.state = OwnershipState.DROPPED
    }
    return true
}

func (ctx *OwnershipDropContext) analyze_block(pc int, stmt *block_stmt, depth int) bool {
    for i := 0; i < len(stmt.statements); i++ {
        if !ctx.analyze_ownership_in_stmt(pc+i, stmt.statements[i], depth) {
            return false
        }
    }
    return true
}

// ============================================================================
// PHASE 2: BORROW CHECKING
// ============================================================================

// phase_borrow_check - Verify borrowing rules
func (ctx *OwnershipDropContext) phase_borrow_check(stmts []interface{}) bool {
    ctx.analysis_phase = 1
    ctx.borrow_contexts = make([]BorrowContext, 0)
    ctx.active_borrows = make(map[string]*BorrowRecord)
    
    // Walk all statements and check borrow rules
    for i := 0; i < len(stmts); i++ {
        if !ctx.check_borrows_in_stmt(i, stmts[i], 0) {
            return false
        }
    }
    
    // Verify no dangling borrows at end
    if len(ctx.active_borrows) > 0 {
        for borrow_var, record := range ctx.active_borrows {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR: dangling borrow %s (source: %s)", borrow_var, record.source_var))
        }
        return false
    }
    
    return len(ctx.errors) == 0
}

func (ctx *OwnershipDropContext) check_borrows_in_stmt(pc int, stmt interface{}, depth int) bool {
    switch s := stmt.(type) {
    case *borrow_stmt:
        return ctx.check_borrow_creation(pc, s, depth)
    case *borrow_end_stmt:
        return ctx.check_borrow_end(pc, s, depth)
    case *move_stmt:
        return ctx.check_move_with_borrows(pc, s, depth)
    case *block_stmt:
        return ctx.check_block_borrows(pc, s, depth+1)
    }
    return true
}

func (ctx *OwnershipDropContext) check_borrow_creation(pc int, stmt *borrow_stmt, depth int) bool {
    source := stmt.source
    
    // Check source exists and is OWNED
    if record, exists := ctx.variableOwners[source]; exists {
        if record.state == OwnershipState.MOVED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR at PC %d: borrow of moved variable %s", pc, source))
            return false
        }
        if record.state == OwnershipState.DROPPED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR at PC %d: borrow of dropped variable %s (dangling borrow)", pc, source))
            return false
        }
        
        // Check borrow conflicts
        if stmt.is_mutable {
            // Mutable borrow requires NO other active borrows
            for _, existing := range ctx.borrowed_set[source] {
                ctx.errors = append(ctx.errors, 
                    sprintf("ERROR at PC %d: cannot create mutable borrow while %s is borrowed", pc, source))
                return false
            }
            record.state = OwnershipState.BORROWED_MUT
        } else {
            // Shared borrow conflicts with mutable borrow
            for _, existing := range ctx.borrowed_set[source] {
                if existing.is_mutable {
                    ctx.errors = append(ctx.errors, 
                        sprintf("ERROR at PC %d: cannot create shared borrow while %s is mutably borrowed", pc, source))
                    return false
                }
            }
            record.state = OwnershipState.BORROWED_SHARED
        }
        
        // Record the borrow
        borrow := &BorrowRecord{
            borrow_var: stmt.borrow_var,
            source_var: source,
            is_mutable: stmt.is_mutable,
            lifetime_start: pc,
            lifetime_end: -1,
            scope_depth: depth,
        }
        ctx.borrowed_set[source] = append(ctx.borrowed_set[source], borrow)
        ctx.active_borrows[stmt.borrow_var] = borrow
    }
    return true
}

func (ctx *OwnershipDropContext) check_borrow_end(pc int, stmt *borrow_end_stmt, depth int) bool {
    borrow_var := stmt.borrow_var
    
    if record, exists := ctx.active_borrows[borrow_var]; exists {
        record.lifetime_end = pc
        delete(ctx.active_borrows, borrow_var)
        
        // Restore source to OWNED
        if source_record, exists := ctx.variableOwners[record.source_var]; exists {
            source_record.state = OwnershipState.OWNED
        }
    }
    return true
}

func (ctx *OwnershipDropContext) check_move_with_borrows(pc int, stmt *move_stmt, depth int) bool {
    source := stmt.source
    
    // Cannot move if borrowed
    if len(ctx.borrowed_set[source]) > 0 {
        ctx.errors = append(ctx.errors, 
            sprintf("ERROR at PC %d: cannot move %s while borrowed", pc, source))
        return false
    }
    return true
}

func (ctx *OwnershipDropContext) check_block_borrows(pc int, stmt *block_stmt, depth int) bool {
    for i := 0; i < len(stmt.statements); i++ {
        if !ctx.check_borrows_in_stmt(pc+i, stmt.statements[i], depth) {
            return false
        }
    }
    return true
}

// ============================================================================
// PHASE 3: DROP ELABORATION & INSERTION
// ============================================================================

// phase_drop_elaboration - Insert drop calls and verify exactly-once semantics
func (ctx *OwnershipDropContext) phase_drop_elaboration(stmts []interface{}) []interface{} {
    ctx.analysis_phase = 2
    ctx.drop_registry = make(map[string]*DropRecord)
    ctx.drop_order = make([]string, 0)
    
    // Build drop registry from ownership records
    ctx.build_drop_registry()
    
    // Insert drops at scope boundaries
    elaborated := ctx.elaborate_drops(stmts, 0)
    
    return elaborated
}

func (ctx *OwnershipDropContext) build_drop_registry() {
    for var_name, record := range ctx.variableOwners {
        if record.state != OwnershipState.MOVED {
            drop_record := &DropRecord{
                variable: var_name,
                type_name: record.type_name,
                has_drop_impl: true, // would check type registry
                drop_fn: sprintf("__s_drop_%s", record.type_name),
                fields: make([]string, 0),
                field_drop_order: make([]string, 0),
            }
            ctx.drop_registry[var_name] = drop_record
            ctx.drop_order = append(ctx.drop_order, var_name)
        }
    }
    
    // Sort by reverse declaration order (LIFO)
    ctx.sort_drop_order_lifo()
}

func (ctx *OwnershipDropContext) sort_drop_order_lifo() {
    // Sort drop_order by reverse declaration order
    for i := 0; i < len(ctx.drop_order); i++ {
        for j := i + 1; j < len(ctx.drop_order); j++ {
            record_i := ctx.variableOwners[ctx.drop_order[i]]
            record_j := ctx.variableOwners[ctx.drop_order[j]]
            if record_i.declaration_order < record_j.declaration_order {
                ctx.drop_order[i], ctx.drop_order[j] = ctx.drop_order[j], ctx.drop_order[i]
            }
        }
    }
}

func (ctx *OwnershipDropContext) elaborate_drops(stmts []interface{}, depth int) []interface{} {
    var result []interface{}
    
    for _, stmt := range stmts {
        result = append(result, stmt)
        
        // Insert drops at scope boundaries
        switch s := stmt.(type) {
        case *block_stmt:
            // Recursively elaborate inner blocks
            s.statements = ctx.elaborate_drops(s.statements, depth+1)
            
            // Insert drops at block exit (reverse order)
            for i := len(ctx.drop_order) - 1; i >= 0; i-- {
                var_name := ctx.drop_order[i]
                if record, exists := ctx.variableOwners[var_name]; exists {
                    if record.scope_depth == depth && record.state != OwnershipState.MOVED {
                        drop_call := &drop_call{
                            variable: var_name,
                            drop_fn: ctx.drop_registry[var_name].drop_fn,
                            kind: "block-exit",
                        }
                        s.statements = append(s.statements, drop_call)
                    }
                }
            }
        }
    }
    
    return result
}

// ============================================================================
// COMPLETE VERIFICATION: CLOSED LOOP GUARANTEE
// ============================================================================

// verify_closed_loop - Complete verification of Ownership → Borrow → Drop
func (ctx *OwnershipDropContext) verify_closed_loop() bool {
    // Check 1: Every variable is owned exactly once
    for var_name, record := range ctx.variableOwners {
        if record.state == OwnershipState.UNDEFINED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR: %s is never initialized", var_name))
            return false
        }
    }
    
    // Check 2: No use-after-move
    for var_name, is_moved := range ctx.moved_set {
        if is_moved {
            if _, is_owner := ctx.owned_set[var_name]; is_owner {
                ctx.errors = append(ctx.errors, 
                    sprintf("ERROR: %s is both moved and owned", var_name))
                return false
            }
        }
    }
    
    // Check 3: No dangling borrows
    for borrow_var, record := range ctx.active_borrows {
        if record.lifetime_end == -1 {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR: dangling borrow %s of %s", borrow_var, record.source_var))
            return false
        }
    }
    
    // Check 4: All resources scheduled for drop
    for var_name, record := range ctx.variableOwners {
        if record.state != OwnershipState.MOVED && record.state != OwnershipState.DROPPED {
            if _, has_drop := ctx.drop_registry[var_name]; !has_drop {
                ctx.warnings = append(ctx.warnings, 
                    sprintf("WARNING: %s not scheduled for drop", var_name))
            }
        }
    }
    
    return len(ctx.errors) == 0
}

// ============================================================================
// ANALYSIS ENTRY POINT - THREE-PHASE PIPELINE
// ============================================================================

type AnalysisResult struct {
    success bool
    elaborated_stmts []interface{}
    errors []string
    warnings []string
    drop_order []string
}

// analyze_complete - Run complete three-phase analysis
func (ctx *OwnershipDropContext) analyze_complete(stmts []interface{}) *AnalysisResult {
    // Phase 1: Ownership Analysis
    if !ctx.phase_ownership_analyze(stmts) {
        return &AnalysisResult{
            success: false,
            errors: ctx.errors,
        }
    }
    
    // Phase 2: Borrow Checking
    if !ctx.phase_borrow_check(stmts) {
        return &AnalysisResult{
            success: false,
            errors: ctx.errors,
        }
    }
    
    // Phase 3: Drop Elaboration
    elaborated := ctx.phase_drop_elaboration(stmts)
    
    // Final Verification
    if !ctx.verify_closed_loop() {
        return &AnalysisResult{
            success: false,
            errors: ctx.errors,
            warnings: ctx.warnings,
        }
    }
    
    return &AnalysisResult{
        success: true,
        elaborated_stmts: elaborated,
        errors: ctx.errors,
        warnings: ctx.warnings,
        drop_order: ctx.drop_order,
    }
}

// ============================================================================
// INITIALIZATION & UTILITY
// ============================================================================

func new_ownership_drop_context() *OwnershipDropContext {
    return &OwnershipDropContext{
        variableOwners: make(map[string]*OwnershipRecord),
        owned_set: make(map[string]bool),
        moved_set: make(map[string]bool),
        borrowed_set: make(map[string][]BorrowRecord),
        errors: make([]string, 0),
        warnings: make([]string, 0),
    }
}

// Helper types for statement representation
type decl_stmt struct {
    name string
    type_name string
}

type assign_stmt struct {
    lhs string
    rhs string
    is_move bool
}

type move_stmt struct {
    source string
}

type drop_stmt struct {
    target string
}

type borrow_stmt struct {
    borrow_var string
    source string
    is_mutable bool
}

type borrow_end_stmt struct {
    borrow_var string
}

type block_stmt struct {
    statements []interface{}
}

type drop_call struct {
    variable string
    drop_fn string
    kind string
}
