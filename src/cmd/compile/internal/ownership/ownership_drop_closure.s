package compile.internal.ownership

type OwnershipDropContext struct {
    variableOwners map[string]*OwnershipRecord
    owned_set map[string]bool
    moved_set map[string]bool
    borrowed_set map[string][]BorrowRecord
    borrow_contexts []BorrowContext
    active_borrows map[string]*BorrowRecord
    drop_registry map[string]*DropRecord
    drop_order []string
    analysis_phase int
    errors []string
    warnings []string
}

type OwnershipRecord struct {
    name string
    type_name string
    state int
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

func (ctx *OwnershipDropContext) phase_ownership_analyze(stmts []interface{}) bool {
    ctx.analysis_phase = 0
    ctx.variableOwners = make(map[string]*OwnershipRecord)
    ctx.owned_set = make(map[string]bool)
    ctx.moved_set = make(map[string]bool)
    ctx.collect_declarations(stmts, 0)
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
    if stmt.is_move {
        rhs_var := stmt.rhs
        if record, exists := ctx.variableOwners[rhs_var]; exists {
            if record.state != OwnershipState.OWNED {
                ctx.errors = append(ctx.errors, 
                    sprintf("ERROR at PC %d: Cannot move %s from state %d", pc, rhs_var, record.state))
                return false
            }
            
            record.state = OwnershipState.MOVED
            ctx.moved_set[rhs_var] = true
            delete(ctx.owned_set, rhs_var)
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

func (ctx *OwnershipDropContext) phase_borrow_check(stmts []interface{}) bool {
    ctx.analysis_phase = 1
    ctx.borrow_contexts = make([]BorrowContext, 0)
    ctx.active_borrows = make(map[string]*BorrowRecord)
    for i := 0; i < len(stmts); i++ {
        if !ctx.check_borrows_in_stmt(i, stmts[i], 0) {
            return false
        }
    }
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
        if stmt.is_mutable {
            for _, existing := range ctx.borrowed_set[source] {
                ctx.errors = append(ctx.errors, 
                    sprintf("ERROR at PC %d: cannot create mutable borrow while %s is borrowed", pc, source))
                return false
            }
            record.state = OwnershipState.BORROWED_MUT
        } else {
            for _, existing := range ctx.borrowed_set[source] {
                if existing.is_mutable {
                    ctx.errors = append(ctx.errors, 
                        sprintf("ERROR at PC %d: cannot create shared borrow while %s is mutably borrowed", pc, source))
                    return false
                }
            }
            record.state = OwnershipState.BORROWED_SHARED
        }
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
        if source_record, exists := ctx.variableOwners[record.source_var]; exists {
            source_record.state = OwnershipState.OWNED
        }
    }
    return true
}

func (ctx *OwnershipDropContext) check_move_with_borrows(pc int, stmt *move_stmt, depth int) bool {
    source := stmt.source
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

func (ctx *OwnershipDropContext) phase_drop_elaboration(stmts []interface{}) []interface{} {
    ctx.analysis_phase = 2
    ctx.drop_registry = make(map[string]*DropRecord)
    ctx.drop_order = make([]string, 0)
    ctx.build_drop_registry()
    elaborated := ctx.elaborate_drops(stmts, 0)
    return elaborated
}

func (ctx *OwnershipDropContext) build_drop_registry() {
    for var_name, record := range ctx.variableOwners {
        if record.state != OwnershipState.MOVED {
            drop_record := &DropRecord{
                variable: var_name,
                type_name: record.type_name,
                has_drop_impl: true,
                drop_fn: sprintf("__s_drop_%s", record.type_name),
                fields: make([]string, 0),
                field_drop_order: make([]string, 0),
            }
            ctx.drop_registry[var_name] = drop_record
            ctx.drop_order = append(ctx.drop_order, var_name)
    }
    ctx.sort_drop_order_lifo()
}

func (ctx *OwnershipDropContext) sort_drop_order_lifo() {
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
        switch s := stmt.(type) {
        case *block_stmt:
            s.statements = ctx.elaborate_drops(s.statements, depth+1)
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

func (ctx *OwnershipDropContext) verify_closed_loop() bool {
    for var_name, record := range ctx.variableOwners {
        if record.state == OwnershipState.UNDEFINED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR: %s is never initialized", var_name))
            return false
        }
    }
    for var_name, is_moved := range ctx.moved_set {
        if is_moved {
            if _, is_owner := ctx.owned_set[var_name]; is_owner {
                ctx.errors = append(ctx.errors, 
                    sprintf("ERROR: %s is both moved and owned", var_name))
                return false
            }
        }
    }
    for borrow_var, record := range ctx.active_borrows {
        if record.lifetime_end == -1 {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR: dangling borrow %s of %s", borrow_var, record.source_var))
            return false
        }
    }
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

type AnalysisResult struct {
    success bool
    elaborated_stmts []interface{}
    errors []string
    warnings []string
    drop_order []string
}

func (ctx *OwnershipDropContext) analyze_complete(stmts []interface{}) *AnalysisResult {
    if !ctx.phase_ownership_analyze(stmts) {
        return &AnalysisResult{
            success: false,
            errors: ctx.errors,
        }
    }
    if !ctx.phase_borrow_check(stmts) {
        return &AnalysisResult{
            success: false,
            errors: ctx.errors,
        }
    }
    elaborated := ctx.phase_drop_elaboration(stmts)
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
