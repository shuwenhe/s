package compile.internal.ownership
type DropElaborator struct {
ctx OwnershipContext*
}

func NewDropElaborator(OwnershipContext* ctx) DropElaborator* {
    return DropElaborator*{
        ctx: ctx,
    }
}

func (DropElaborator* de) ElaborateDrops(stmts interface{}[]) interface{}[] {
    var result interface{}[]
    for _, stmt := range stmts {
        result = append(result, de.elaborateStatement(stmt))
    }
    return result
}

func (DropElaborator* de) elaborateStatement(stmt interface{}) interface{} {
    switch s := stmt.(type) {
case BlockStmt*:
        return de.elaborateBlock(s)
case ReturnStmt*:
        return de.elaborateReturn(s)
case IfStmt*:
        return de.elaborateIf(s)
case LoopStmt*:
        return de.elaborateLoop(s)
    default:
        return stmt
    }
}

func (DropElaborator* de) elaborateBlock(BlockStmt* block) BlockStmt* {
    var stmts interface{}[]
    for _, stmt := range block.Statements {
        stmts = append(stmts, de.elaborateStatement(stmt))
    }
    dropsNeeded := de.collectDropsForBlock(block)
    for _, dropVar := range dropsNeeded {
        stmts = append(stmts, DropCall*{
            Variable: dropVar,
            Kind:     "explicit",
        })
    }
    return BlockStmt*{
        Statements: stmts,
    }
}

func (DropElaborator* de) elaborateReturn(ReturnStmt* ret) interface{} {
    dropsNeeded := de.collectDropsForReturn()
    var result interface{}[]
    for _, dropVar := range dropsNeeded {
        result = append(result, DropCall*{
            Variable: dropVar,
            Kind:     "return-cleanup",
        })
    }
    result = append(result, ret)
    return BlockStmt*{
        Statements: result,
    }
}

func (DropElaborator* de) elaborateIf(IfStmt* ifStmt) IfStmt* {
    elaboratedThen := de.elaborateStatement(ifStmt.ThenBranch)
    var elaboratedElse interface{}
    if ifStmt.ElseBranch != nil {
        elaboratedElse = de.elaborateStatement(ifStmt.ElseBranch)
    }
    return IfStmt*{
        Condition:   ifStmt.Condition,
        ThenBranch:  elaboratedThen,
        ElseBranch:  elaboratedElse,
    }
}

func (DropElaborator* de) elaborateLoop(LoopStmt* loop) LoopStmt* {
    elaboratedBody := de.elaborateStatement(loop.Body)
    return LoopStmt*{
        Condition: loop.Condition,
        Body:      elaboratedBody,
    }
}

func (DropElaborator* de) collectDropsForBlock(BlockStmt* block) string[] {
    var drops string[]
    return drops
}

func (DropElaborator* de) collectDropsForReturn() string[] {
    var drops string[]
    return drops
}

func (DropElaborator* de) VerifyExactlyOnceDrop(elaborated interface{}[]) bool {
    dropCounts := make(map[string]int)
    de.countDrops(elaborated, dropCounts)
    for variable, count := range dropCounts {
        if count == 0 {
            de.ctx.AddError(errorf("variable %s never dropped", variable))
            return false
        }
        if count > 1 {
            de.ctx.AddError(errorf("variable %s dropped %d times (double-drop)", 
                variable, count))
            return false
        }
    }
    return !de.ctx.HasErrors()
}

func (DropElaborator* de) countDrops(stmts interface{}[], counts map[string]int) {
    for _, stmt := range stmts {
        switch s := stmt.(type) {
case DropCall*:
            counts[s.Variable]++
case BlockStmt*:
            de.countDrops(s.Statements, counts)
        }
    }
}

func (DropElaborator* de) VerifyNoUseAfterDrop(stmts interface{}[]) bool {
    droppedVars := make(map[string]bool)
    return de.checkUseAfterDrop(stmts, droppedVars)
}

func (DropElaborator* de) checkUseAfterDrop(stmts interface{}[], 
    droppedVars map[string]bool) bool {
    for _, stmt := range stmts {
        switch s := stmt.(type) {
case DropCall*:
            if droppedVars[s.Variable] {
                de.ctx.AddError(errorf("use-after-drop: variable %s", s.Variable))
                return false
            }
            droppedVars[s.Variable] = true
case UseStmt*:
            if droppedVars[s.Variable] {
                de.ctx.AddError(errorf("use-after-drop: using %s", s.Variable))
                return false
            }
case BlockStmt*:
            scopeDropped := make(map[string]bool)
            for k, v := range droppedVars {
                scopeDropped[k] = v
            }
            if !de.checkUseAfterDrop(s.Statements, scopeDropped) {
                return false
            }
        }
    }
    return true
}

func (DropElaborator* de) VerifyPartialMoveDrops(stmts interface{}[]) bool {
    return true  // Placeholder
}

func (DropElaborator* de) GetDropOrder(typeName string) string[] {
    typeClass := de.ctx.classify_type(typeName)
    result := make(string[], len(typeClass.DropOrder))
    for i, field := range typeClass.DropOrder {
        result[len(result)-1-i] = field
    }
    return result
}
type BlockStmt struct {
    Statements interface{}[]
}
type IfStmt struct {
    Condition  interface{}
    ThenBranch interface{}
    ElseBranch interface{}
}
type LoopStmt struct {
    Condition interface{}
    Body      interface{}
}
type DropCall struct {
    Variable string
    Kind     string  // "explicit", "return-cleanup", "error-cleanup"
}
type DropSummary struct {
    MustDrop string[]
    MayDrop string[]
    DropOrder string[]
    FieldDrops map[string]string[]
}

func (DropElaborator* de) GenerateDropSummary(BlockStmt* block) DropSummary* {
    summary := DropSummary*{
        MustDrop:   make(string[], 0),
        MayDrop:    make(string[], 0),
        DropOrder:  make(string[], 0),
        FieldDrops: make(map[string]string[]),
    }
    return summary
}
