package compile.internal.ownership
type DropElaborator struct {
    ctx *OwnershipContext
}
func NewDropElaborator(ctx *OwnershipContext) *DropElaborator {
    return &DropElaborator{
        ctx: ctx,
    }
}
func (de *DropElaborator) ElaborateDrops(stmts interface{}[]) interface{}[] {
    var result interface{}[]
    for _, stmt := range stmts {
        result = append(result, de.elaborateStatement(stmt))
    }
    return result
}
func (de *DropElaborator) elaborateStatement(stmt interface{}) interface{} {
    switch s := stmt.(type) {
    case *BlockStmt:
        return de.elaborateBlock(s)
    case *ReturnStmt:
        return de.elaborateReturn(s)
    case *IfStmt:
        return de.elaborateIf(s)
    case *LoopStmt:
        return de.elaborateLoop(s)
    default:
        return stmt
    }
}
func (de *DropElaborator) elaborateBlock(block *BlockStmt) *BlockStmt {
    var stmts interface{}[]
    for _, stmt := range block.Statements {
        stmts = append(stmts, de.elaborateStatement(stmt))
    }
    dropsNeeded := de.collectDropsForBlock(block)
    for _, dropVar := range dropsNeeded {
        stmts = append(stmts, &DropCall{
            Variable: dropVar,
            Kind:     "explicit",
        })
    }
    return &BlockStmt{
        Statements: stmts,
    }
}
func (de *DropElaborator) elaborateReturn(ret *ReturnStmt) interface{} {
    dropsNeeded := de.collectDropsForReturn()
    var result interface{}[]
    for _, dropVar := range dropsNeeded {
        result = append(result, &DropCall{
            Variable: dropVar,
            Kind:     "return-cleanup",
        })
    }
    result = append(result, ret)
    return &BlockStmt{
        Statements: result,
    }
}
func (de *DropElaborator) elaborateIf(ifStmt *IfStmt) *IfStmt {
    elaboratedThen := de.elaborateStatement(ifStmt.ThenBranch)
    var elaboratedElse interface{}
    if ifStmt.ElseBranch != nil {
        elaboratedElse = de.elaborateStatement(ifStmt.ElseBranch)
    }
    return &IfStmt{
        Condition:   ifStmt.Condition,
        ThenBranch:  elaboratedThen,
        ElseBranch:  elaboratedElse,
    }
}
func (de *DropElaborator) elaborateLoop(loop *LoopStmt) *LoopStmt {
    elaboratedBody := de.elaborateStatement(loop.Body)
    return &LoopStmt{
        Condition: loop.Condition,
        Body:      elaboratedBody,
    }
}
func (de *DropElaborator) collectDropsForBlock(block *BlockStmt) string[] {
    var drops string[]
    return drops
}
func (de *DropElaborator) collectDropsForReturn() string[] {
    var drops string[]
    return drops
}
func (de *DropElaborator) VerifyExactlyOnceDrop(elaborated interface{}[]) bool {
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
func (de *DropElaborator) countDrops(stmts interface{}[], counts map[string]int) {
    for _, stmt := range stmts {
        switch s := stmt.(type) {
        case *DropCall:
            counts[s.Variable]++
        case *BlockStmt:
            de.countDrops(s.Statements, counts)
        }
    }
}
func (de *DropElaborator) VerifyNoUseAfterDrop(stmts interface{}[]) bool {
    droppedVars := make(map[string]bool)
    return de.checkUseAfterDrop(stmts, droppedVars)
}
func (de *DropElaborator) checkUseAfterDrop(stmts interface{}[], 
    droppedVars map[string]bool) bool {
    for _, stmt := range stmts {
        switch s := stmt.(type) {
        case *DropCall:
            if droppedVars[s.Variable] {
                de.ctx.AddError(errorf("use-after-drop: variable %s", s.Variable))
                return false
            }
            droppedVars[s.Variable] = true
        case *UseStmt:
            if droppedVars[s.Variable] {
                de.ctx.AddError(errorf("use-after-drop: using %s", s.Variable))
                return false
            }
        case *BlockStmt:
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
func (de *DropElaborator) VerifyPartialMoveDrops(stmts interface{}[]) bool {
    return true  // Placeholder
}
func (de *DropElaborator) GetDropOrder(typeName string) string[] {
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
func (de *DropElaborator) GenerateDropSummary(block *BlockStmt) *DropSummary {
    summary := &DropSummary{
        MustDrop:   make(string[], 0),
        MayDrop:    make(string[], 0),
        DropOrder:  make(string[], 0),
        FieldDrops: make(map[string]string[]),
    }
    return summary
}
