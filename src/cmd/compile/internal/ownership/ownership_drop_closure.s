package compile.internal.ownership
struct ownership_drop_context {
    variableOwners map[string]*ownership_record
    owned_set map[string]bool
    moved_set map[string]bool
    borrowed_set map[string]borrow_record[]
    borrow_contexts borrow_context[]
    active_borrows map[string]*borrow_record
    drop_registry map[string]*drop_record
    drop_order string[]
    analysis_phase int
    errors string[]
    warnings string[]
}

struct ownership_record {
    name string
    type_name string
    state int
    declaration_order int
    scope_depth int
    is_param bool
}

struct borrow_record {
    borrow_var string
    source_var string
    is_mutable bool
    lifetime_start int
    lifetime_end int
    scope_depth int
}

struct drop_record {
    variable string
    type_name string
    has_drop_impl bool
    drop_fn string
    fields string[]
    field_drop_order string[]
}

struct ownership_state {
    undefined = 0
    owned = 1
    borrowed_shared = 2
    borrowed_mut = 3
    moved = 4
    dropped = 5
}

func (ownership_drop_context* ctx) phase_ownership_analyze(stmts interface{}[]) bool {
    ctx.analysis_phase = 0
    ctx.variable_owners = make(map[string]*ownership_record)
    ctx.owned_set = make(map[string]bool)
    ctx.moved_set = make(map[string]bool)
    ctx.borrow_contexts = make(borrow_context[], 0)
    ctx.active_borrows = make(map[string]*borrow_record)
    ctx.collect_declarations(stmts, 0)
    for i := 0; i < len(stmts); i++ {
        if !ctx.analyze_ownership_in_stmt(i, stmts[i], 0) {
            return false
        }
    }
    return len(ctx.errors) == 0
}

func (ownership_drop_context* ctx) collect_declarations(stmts interface{}[], int depth) {
    for _, stmt := range stmts {
        ctx.collect_from_stmt(stmt, depth)
    }
}

func (ownership_drop_context* ctx) collect_from_stmt(stmt interface{}, int depth) {
    switch s := stmt.(type) {
case decl_stmt*:
        owner := ownership_record*{
            name: s.name,
            type_name: s.type_name,
            state: ownership_state.OWNED,
            declaration_order: len(ctx.variable_owners),
            scope_depth: depth,
            is_param: false,
        }
        ctx.variable_owners[s.name] = owner
        ctx.owned_set[s.name] = true
    }
}

func (ownership_drop_context* ctx) analyze_ownership_in_stmt(int pc, stmt interface{}, int depth) bool {
    switch s := stmt.(type) {
case assign_stmt*:
        return ctx.analyze_assign(pc, s, depth)
case move_stmt*:
        return ctx.analyze_move(pc, s, depth)
case drop_stmt*:
        return ctx.analyze_drop(pc, s, depth)
case block_stmt*:
        return ctx.analyze_block(pc, s, depth+1)
    }
    return true
}

func (ownership_drop_context* ctx) analyze_assign(int pc, stmt* assign_stmt, int depth) bool {
    if stmt.is_move {
        rhs_var := stmt.rhs
        if record, exists := ctx.variable_owners[rhs_var]; exists {
            if record.state != ownership_state.OWNED {
                ctx.errors = append(ctx.errors, 
                    sprintf("ERROR at PC %d: Cannot move %s from state %d", pc, rhs_var, record.state))
                return false
            }
            record.state = ownership_state.MOVED
            ctx.moved_set[rhs_var] = true
            delete(ctx.owned_set, rhs_var)
            if lhs_record, exists := ctx.variable_owners[stmt.lhs]; exists {
                lhs_record.state = ownership_state.OWNED
                ctx.owned_set[stmt.lhs] = true
            }
        }
    }
    return true
}

func (ownership_drop_context* ctx) analyze_move(int pc, stmt* move_stmt, int depth) bool {
    if record, exists := ctx.variable_owners[stmt.source]; exists {
        if record.state == ownership_state.MOVED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR at PC %d: double-move of %s", pc, stmt.source))
            return false
        }
        if record.state == ownership_state.DROPPED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR at PC %d: use-after-drop of %s", pc, stmt.source))
            return false
        }
        record.state = ownership_state.MOVED
    }
    return true
}

func (ownership_drop_context* ctx) analyze_drop(int pc, stmt* drop_stmt, int depth) bool {
    if record, exists := ctx.variable_owners[stmt.target]; exists {
        if record.state == ownership_state.DROPPED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR at PC %d: double-drop of %s", pc, stmt.target))
            return false
        }
        record.state = ownership_state.DROPPED
    }
    return true
}

func (ownership_drop_context* ctx) analyze_block(int pc, stmt* block_stmt, int depth) bool {
    for i := 0; i < len(stmt.statements); i++ {
        if !ctx.analyze_ownership_in_stmt(pc+i, stmt.statements[i], depth) {
            return false
        }
    }
    return true
}

func (ownership_drop_context* ctx) phase_borrow_check(stmts interface{}) bool {
    ctx.analysis_phase = 1
    ctx.active_borrows = make(map[string]*borrow_record)
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

func (ownership_drop_context* ctx) check_borrows_in_stmt(int pc, stmt interface{}, int depth) bool {
    switch s := stmt.(type) {
case borrow_stmt*:
        return ctx.check_borrow_creation(pc, s, depth)
case borrow_end_stmt*:
        return ctx.check_borrow_end(pc, s, depth)
case move_stmt*:
        return ctx.check_move_with_borrows(pc, s, depth)
case block_stmt*:
        return ctx.check_block_borrows(pc, s, depth+1)
    }
    return true
}

func (ownership_drop_context* ctx) check_borrow_creation(int pc, stmt* borrow_stmt, int depth) bool {
    source := stmt.source
    if record, exists := ctx.variable_owners[source]; exists {
        if record.state == ownership_state.MOVED {
            ctx.errors = append(ctx.errors, 
                sprintf("ERROR at PC %d: borrow of moved variable %s", pc, source))
            return false
        }
        if record.state == ownership_state.DROPPED {
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
            record.state = ownership_state.borrowed_mut
        } else {
            for _, existing := range ctx.borrowed_set[source] {
                if existing.is_mutable {
                    ctx.errors = append(ctx.errors, 
                        sprintf("ERROR at PC %d: cannot create shared borrow while %s is mutably borrowed", pc, source))
                    return false
                }
            }
            record.state = ownership_state.borrowed_shared
        }
        borrow := borrow_record*{
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

func (ownership_drop_context* ctx) check_borrow_end(int pc, stmt* borrow_end_stmt, int depth) bool {
    borrow_var := stmt.borrow_var
    if record, exists := ctx.active_borrows[borrow_var]; exists {
        record.lifetime_end = pc
        delete(ctx.active_borrows, borrow_var)
        if source_record, exists := ctx.variable_owners[record.source_var]; exists {
            source_record.state = ownership_state.OWNED
        }
    }
    return true
}

func (ownership_drop_context* ctx) check_move_with_borrows(int pc, stmt* move_stmt, int depth) bool {
    source := stmt.source
    if len(ctx.borrowed_set[source]) > 0 {
        ctx.errors = append(ctx.errors, 
            sprintf("ERROR at PC %d: cannot move %s while borrowed", pc, source))
        return false
    }
    return true
}

func (ownership_drop_context* ctx) check_block_borrows(int pc, stmt* block_stmt, int depth) bool {
    for i := 0; i < len(stmt.statements); i++ {
        if !ctx.check_borrows_in_stmt(pc+i, stmt.statements[i], depth) {
            return false
        }
    }
    return true
}

func (ownership_drop_context* ctx) phase_drop_elaboration(stmts interface{}) interface{} {
    ctx.analysis_phase = 2
    ctx.drop_registry = make(map[string]*drop_record)
    ctx.drop_order = make(string[], 0)
    ctx.build_drop_registry()
    elaborated := ctx.elaborate_drops(stmts, 0)
    return elaborated
}

func (ownership_drop_context* ctx) build_drop_registry() {
    for var_name, record := range ctx.variable_owners {
        if record.state != ownership_state.MOVED {
            drop_record := drop_record*{
                variable: var_name,
                type_name: record.type_name,
                has_drop_impl: true,
                drop_fn: sprintf("__s_drop_%s", record.type_name),
                fields: make(string[], 0),
                field_drop_order: make(string[], 0),
            }
            ctx.drop_registry[var_name] = drop_record
            ctx.drop_order = append(ctx.drop_order, var_name)
    }
    ctx.sort_drop_order_lifo()
}

func (ownership_drop_context* ctx) sort_drop_order_lifo() {
    for i := 0; i < len(ctx.drop_order); i++ {
        for j := i + 1; j < len(ctx.drop_order); j++ {
            record_i := ctx.variable_owners[ctx.drop_order[i]]
            record_j := ctx.variable_owners[ctx.drop_order[j]]
            if record_i.declaration_order < record_j.declaration_order {
                ctx.drop_order[i], ctx.drop_order[j] = ctx.drop_order[j], ctx.drop_order[i]
            }
        }
    }
}

func (ownership_drop_context* ctx) elaborate_drops(stmts interface{}, int depth) interface{} {
    var result interface{}[]
    for _, stmt := range stmts {
        result = append(result, stmt)
        switch s := stmt.(type) {
case block_stmt*:
            s.statements = ctx.elaborate_drops(s.statements, depth+1)
            for i := len(ctx.drop_order) - 1; i >= 0; i-- {
                var_name := ctx.drop_order[i]
                if record, exists := ctx.variable_owners[var_name]; exists {
                    if record.scope_depth == depth && record.state != ownership_state.MOVED {
                        drop_call := drop_call*{
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

func (ownership_drop_context* ctx) verify_closed_loop() bool {
    for var_name, record := range ctx.variable_owners {
        if record.state == ownership_state.UNDEFINED {
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
    for var_name, record := range ctx.variable_owners {
        if record.state != ownership_state.MOVED && record.state != ownership_state.DROPPED {
            if _, has_drop := ctx.drop_registry[var_name]; !has_drop {
                ctx.warnings = append(ctx.warnings, 
                    sprintf("WARNING: %s not scheduled for drop", var_name))
            }
        }
    }
    return len(ctx.errors) == 0
}

struct analysis_result {
    success bool
    elaborated_stmts interface{}{}
    errors string[]
    warnings string[]
    drop_order string[]
}

func (ownership_drop_context* ctx) analyze_complete(stmts interface{}) analysis_result* {
    if !ctx.phase_ownership_analyze(stmts) {
        return analysis_result*{
            success: false,
            errors: ctx.errors,
        }
    }
    if !ctx.phase_borrow_check(stmts) {
        return analysis_result*{
            success: false,
            errors: ctx.errors,
        }
    }
    elaborated := ctx.phase_drop_elaboration(stmts)
    if !ctx.verify_closed_loop() {
        return analysis_result*{
            success: false,
            errors: ctx.errors,
            warnings: ctx.warnings,
        }
    }
    return analysis_result*{
        success: true,
        elaborated_stmts: elaborated,
        errors: ctx.errors,
        warnings: ctx.warnings,
        drop_order: ctx.drop_order,
    }
}

func new_ownership_drop_context() ownership_drop_context* {
    return ownership_drop_context*{
        variable_owners: make(map[string]*ownership_record),
        owned_set: make(map[string]bool),
        moved_set: make(map[string]bool),
        borrowed_set: make(map[string]borrow_record[]),
        errors: make(string[], 0),
        warnings: make(string[], 0),
    }
}

struct decl_stmt {
    name string
    type_name string
}

struct assign_stmt {
    lhs string
    rhs string
    is_move bool
}

struct move_stmt {
    source string
}

struct drop_stmt {
    target string
}

struct borrow_stmt {
    borrow_var string
    source string
    is_mutable bool
}

struct borrow_end_stmt {
    borrow_var string
}

struct block_stmt {
    statements interface{}[]
}

struct drop_call {
    variable string
    drop_fn string
    kind string
}
