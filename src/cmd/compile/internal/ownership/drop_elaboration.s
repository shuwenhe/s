package compile.internal.ownership
struct drop_elaborator {
ctx OwnershipContext*
}

func new_drop_elaborator(OwnershipContext* ctx) drop_elaborator* {
    return drop_elaborator*{
        ctx: ctx,
    }
}

func (drop_elaborator* de) elaborate_drops(stmts interface{}[]) interface{}[] {
    var result interface{}[]
    for _, stmt := range stmts {
        result = append(result, de.elaborate_statement(stmt))
    }
    return result
}

func (drop_elaborator* de) elaborate_statement(stmt interface{}) interface{} {
    switch s := stmt.(type) {
case BlockStmt*:
        return de.elaborate_block(s)
case ReturnStmt*:
        return de.elaborate_return(s)
case IfStmt*:
        return de.elaborate_if(s)
case LoopStmt*:
        return de.elaborate_loop(s)
    default:
        return stmt
    }
}

func (drop_elaborator* de) elaborate_block(BlockStmt* block) BlockStmt* {
    var stmts interface{}[]
    for _, stmt := range block.statements {
        stmts = append(stmts, de.elaborate_statement(stmt))
    }
    drops_needed := de.collect_drops_for_block(block)
    for _, drop_var := range drops_needed {
        stmts = append(stmts, DropCall*{
            variable: drop_var,
            kind:     "explicit",
        })
    }
    return BlockStmt*{
        statements: stmts,
    }
}

func (drop_elaborator* de) elaborate_return(ReturnStmt* ret) interface{} {
    drops_needed := de.collect_drops_for_return()
    var result interface{}[]
    for _, drop_var := range drops_needed {
        result = append(result, DropCall*{
            variable: drop_var,
            kind:     "return-cleanup",
        })
    }
    result = append(result, ret)
    return BlockStmt*{
        statements: result,
    }
}

func (drop_elaborator* de) elaborate_if(IfStmt* ifStmt) IfStmt* {
    elaborated_then := de.elaborate_statement(ifStmt.then_branch)
    var elaborated_else interface{}
    if ifStmt.else_branch != nil {
        elaborated_else = de.elaborate_statement(ifStmt.else_branch)
    }
    return IfStmt*{
        condition:   ifStmt.condition,
        then_branch:  elaborated_then,
        else_branch:  elaborated_else,
    }
}

func (drop_elaborator* de) elaborate_loop(LoopStmt* loop) LoopStmt* {
    elaborated_body := de.elaborate_statement(loop.body)
    return LoopStmt*{
        condition: loop.condition,
        body:      elaborated_body,
    }
}

func (drop_elaborator* de) collect_drops_for_block(BlockStmt* block) string[] {
    var drops string[]
    return drops
}

func (drop_elaborator* de) collect_drops_for_return() string[] {
    var drops string[]
    return drops
}

func (drop_elaborator* de) verify_exactly_once_drop(elaborated interface{}[]) bool {
    drop_counts := make(map[string]int)
    de.count_drops(elaborated, drop_counts)
    for variable, count := range drop_counts {
        if count == 0 {
            de.ctx.add_error(errorf("variable %s never dropped", variable))
            return false
        }
        if count > 1 {
            de.ctx.add_error(errorf("variable %s dropped %d times (double-drop)", 
                variable, count))
            return false
        }
    }
    return !de.ctx.has_errors()
}

func (drop_elaborator* de) count_drops(stmts interface{}[], counts map[string]int) {
    for _, stmt := range stmts {
        switch s := stmt.(type) {
case DropCall*:
            counts[s.variable]++
case BlockStmt*:
            de.count_drops(s.statements, counts)
        }
    }
}

func (drop_elaborator* de) verify_no_use_after_drop(stmts interface{}[]) bool {
    dropped_vars := make(map[string]bool)
    return de.check_use_after_drop(stmts, dropped_vars)
}

func (drop_elaborator* de) check_use_after_drop(stmts interface{}[], 
    dropped_vars map[string]bool) bool {
    for _, stmt := range stmts {
        switch s := stmt.(type) {
case DropCall*:
            if dropped_vars[s.variable] {
                de.ctx.add_error(errorf("use-after-drop: variable %s", s.variable))
                return false
            }
            dropped_vars[s.variable] = true
case UseStmt*:
            if dropped_vars[s.variable] {
                de.ctx.add_error(errorf("use-after-drop: using %s", s.variable))
                return false
            }
case BlockStmt*:
            scope_dropped := make(map[string]bool)
            for k, v := range dropped_vars {
                scope_dropped[k] = v
            }
            if !de.check_use_after_drop(s.statements, scope_dropped) {
                return false
            }
        }
    }
    return true
}

func (drop_elaborator* de) verify_partial_move_drops(stmts interface{}[]) bool {
    return true  // Placeholder
}

func (drop_elaborator* de) get_drop_order(string typeName) string[] {
    type_class := de.ctx.classify_type(typeName)
    result := make(string[], len(type_class.drop_order))
    for i, field := range type_class.drop_order {
        result[len(result)-1-i] = field
    }
    return result
}

struct block_stmt {
    statements interface{}[]
}

struct if_stmt {
    condition  interface{}
    then_branch interface{}
    else_branch interface{}
}

struct loop_stmt {
    condition interface{}
    body      interface{}
}

struct drop_call {
    variable    string
    kind     string  // "explicit", "return-cleanup", "error-cleanup"
}

struct drop_summary {
    must_drop string[]
    may_drop string[]
    drop_order string[]
    field_drops map[string]string[]
}

func (drop_elaborator* de) generate_drop_summary(BlockStmt* block) drop_summary* {
    summary := drop_summary*{
        must_drop:   make(string[], 0),
        may_drop:    make(string[], 0),
        drop_order:  make(string[], 0),
        field_drops: make(map[string]string[]),
    }
    return summary
}
