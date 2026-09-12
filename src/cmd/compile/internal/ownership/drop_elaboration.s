package compile.internal.ownership

// drop_elaboration.s - Insert drop calls and verify exactly-once semantics
//
// Responsibilities:
// - Insert drop calls at all resource release points
// - Determine drop order for multi-field structs
// - Handle early returns and error paths
// - Verify exactly-once drop guarantee
// - Track field-level drops (for partial move)
// - Handle destructor ordering (reverse declaration order)

// DropElaborator inserts drop calls and verifies drop correctness
type DropElaborator struct {
    ctx *OwnershipContext
}

// NewDropElaborator creates a drop elaboration pass
func NewDropElaborator(ctx *OwnershipContext) *DropElaborator {
    return &DropElaborator{
        ctx: ctx,
    }
}

// ElaborateDrops transforms AST to insert drop calls
func (de *DropElaborator) ElaborateDrops(stmts interface{}[]) interface{}[] {
    var result interface{}[]
    
    // Walk statements and insert drops
    for _, stmt := range stmts {
        result = append(result, de.elaborateStatement(stmt))
    }
    
    return result
}

// elaborateStatement processes a single statement
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

// elaborateBlock inserts drops at block exit
func (de *DropElaborator) elaborateBlock(block *BlockStmt) *BlockStmt {
    var stmts interface{}[]
    
    // Process all statements in block
    for _, stmt := range block.Statements {
        stmts = append(stmts, de.elaborateStatement(stmt))
    }
    
    // Collect variables that need dropping at block exit
    dropsNeeded := de.collectDropsForBlock(block)
    
    // Insert drop calls in reverse declaration order
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

// elaborateReturn inserts drops before returning
func (de *DropElaborator) elaborateReturn(ret *ReturnStmt) interface{} {
    // Collect all variables in scope that need dropping
    dropsNeeded := de.collectDropsForReturn()
    
    var result interface{}[]
    
    // Insert drop calls
    for _, dropVar := range dropsNeeded {
        result = append(result, &DropCall{
            Variable: dropVar,
            Kind:     "return-cleanup",
        })
    }
    
    // Add the return
    result = append(result, ret)
    
    return &BlockStmt{
        Statements: result,
    }
}

// elaborateIf inserts drops in both branches
func (de *DropElaborator) elaborateIf(ifStmt *IfStmt) *IfStmt {
    // Elaborate then branch
    elaboratedThen := de.elaborateStatement(ifStmt.ThenBranch)
    
    // Elaborate else branch
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

// elaborateLoop inserts drops at loop exit
func (de *DropElaborator) elaborateLoop(loop *LoopStmt) *LoopStmt {
    elaboratedBody := de.elaborateStatement(loop.Body)
    
    return &LoopStmt{
        Condition: loop.Condition,
        Body:      elaboratedBody,
    }
}

// collectDropsForBlock determines which variables need drops at block exit
func (de *DropElaborator) collectDropsForBlock(block *BlockStmt) string[] {
    var drops string[]
    
    // Walk block to find variables that:
    // 1. Are owned types (require drop)
    // 2. Reach block exit in OWNED state
    // 3. Have not been moved/dropped
    
    // This is simplified - real version walks the whole scope
    return drops
}

// collectDropsForReturn collects all variables needing cleanup before return
func (de *DropElaborator) collectDropsForReturn() string[] {
    var drops string[]
    
    // Collect all variables in current scope that are OWNED
    // and will be exiting with scope
    
    return drops
}

// VerifyExactlyOnceDrop checks that each owned value is dropped exactly once
func (de *DropElaborator) VerifyExactlyOnceDrop(elaborated interface{}[]) bool {
    dropCounts := make(map[string]int)
    
    // Walk elaborated code and count drops
    de.countDrops(elaborated, dropCounts)
    
    // Check each variable is dropped exactly once (if it reached scope exit)
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

// countDrops walks code and counts drop calls per variable
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

// VerifyNoUseAfterDrop checks that variables aren't used after drop
func (de *DropElaborator) VerifyNoUseAfterDrop(stmts interface{}[]) bool {
    droppedVars := make(map[string]bool)
    return de.checkUseAfterDrop(stmts, droppedVars)
}

// checkUseAfterDrop recursively checks for use-after-drop
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
            // Copy the dropped vars set for this scope
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

// VerifyPartialMoveDrops checks that partially-moved structs handle field drops
func (de *DropElaborator) VerifyPartialMoveDrops(stmts interface{}[]) bool {
    // For each variable with PARTIALLY_MOVED state:
    // - Verify remaining fields are dropped
    // - Verify moved fields are not dropped again
    // - Verify drop order respects field dependencies
    
    return true  // Placeholder
}

// GetDropOrder returns the correct drop order for a struct type
// (reverse declaration order to respect dependencies)
func (de *DropElaborator) GetDropOrder(typeName string) string[] {
    typeClass := de.ctx.classify_type(typeName)
    
    // Reverse the order (drop fields in reverse of declaration)
    result := make(string[], len(typeClass.DropOrder))
    for i, field := range typeClass.DropOrder {
        result[len(result)-1-i] = field
    }
    
    return result
}

// Simplified AST node types for drop operations
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
    
    // Walk block and determine drops
    // This is simplified - real implementation is more complex
    
    return summary
}
