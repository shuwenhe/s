package compile.internal.ownership
type drop_elaborator struct {
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
    dropsNeeded := de.collect_drops_for_block(block)
    for _, dropVar := range dropsNeeded {
        stmts = append(stmts, DropCall*{
            variable: dropVar,
            kind:     "explicit",
        })
    }
    return BlockStmt*{
        statements: stmts,
    }
}

func (drop_elaborator* de) elaborate_return(ReturnStmt* ret) interface{} {
    dropsNeeded := de.collect_drops_for_return()
    var result interface{}[]
    for _, dropVar := range dropsNeeded {
        result = append(result, DropCall*{
            variable: dropVar,
            kind:     "return-cleanup",
        })
    }
    result = append(result, ret)
    return BlockStmt*{
        statements: result,
    }
}

func (drop_elaborator* de) elaborate_if(IfStmt* ifStmt) IfStmt* {
    elaboratedThen := de.elaborate_statement(ifStmt.then_branch)
    var elaboratedElse interface{}
    if ifStmt.else_branch != nil {
        elaboratedElse = de.elaborate_statement(ifStmt.else_branch)
    }
    return IfStmt*{
        condition:   ifStmt.condition,
        then_branch:  elaboratedThen,
        else_branch:  elaboratedElse,
    }
}

func (drop_elaborator* de) elaborate_loop(LoopStmt* loop) LoopStmt* {
    elaboratedBody := de.elaborate_statement(loop.body)
    return LoopStmt*{
        condition: loop.condition,
        body:      elaboratedBody,
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
    dropCounts := make(map[string]int)
    de.count_drops(elaborated, dropCounts)
    for variable, count := range dropCounts {
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
    droppedVars := make(map[string]bool)
    return de.check_use_after_drop(stmts, droppedVars)
}

func (drop_elaborator* de) check_use_after_drop(stmts interface{}[], 
    droppedVars map[string]bool) bool {
    for _, stmt := range stmts {
        switch s := stmt.(type) {
case DropCall*:
            if droppedVars[s.variable] {
                de.ctx.add_error(errorf("use-after-drop: variable %s", s.variable))
                return false
            }
            droppedVars[s.variable] = true
case UseStmt*:
            if droppedVars[s.variable] {
                de.ctx.add_error(errorf("use-after-drop: using %s", s.variable))
                return false
            }
case BlockStmt*:
            scopeDropped := make(map[string]bool)
            for k, v := range droppedVars {
                scopeDropped[k] = v
            }
            if !de.check_use_after_drop(s.statements, scopeDropped) {
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
    typeClass := de.ctx.classify_type(typeName)
    result := make(string[], len(typeClass.drop_order))
    for i, field := range typeClass.drop_order {
        result[len(result)-1-i] = field
    }
    return result
}
type block_stmt struct {
    Statements interface{}[]
}
type if_stmt struct {
    Condition  interface{}
    ThenBranch interface{}
    ElseBranch interface{}
}
type loop_stmt struct {
    Condition interface{}
    Body      interface{}
}
type drop_call struct {
    Variable string
    Kind     string  // "explicit", "return-cleanup", "error-cleanup"
}
type drop_summary struct {
    MustDrop string[]
    MayDrop string[]
    DropOrder string[]
    FieldDrops map[string]string[]
}

func (drop_elaborator* de) generate_drop_summary(BlockStmt* block) DropSummary* {
    summary := DropSummary*{
        MustDrop:   make(string[], 0),
        MayDrop:    make(string[], 0),
        drop_order:  make(string[], 0),
        FieldDrops: make(map[string]string[]),
    }
    return summary
}
