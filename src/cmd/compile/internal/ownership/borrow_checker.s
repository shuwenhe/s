package compile.internal.ownership

// borrow_checker.s - Verify borrow semantics
//
// Checks:
// - shared borrow can coexist with other shared borrows
// - mutable borrow must be exclusive (no other borrows or moves)
// - move-while-borrowed (ERROR)
// - use-after-borrow-end
// - borrow conflicts (mutable + any other borrow)
// - dangling borrow (original dropped while borrowed)

// BorrowChecker analyzes borrow scope and conflicts
type BorrowChecker struct {
    ctx *OwnershipContext
}

// NewBorrowChecker creates a borrow checker
func NewBorrowChecker(ctx *OwnershipContext) *BorrowChecker {
    return &BorrowChecker{
        ctx: ctx,
    }
}

// CheckBorrowSemantics performs complete borrow checking
func (bc *BorrowChecker) CheckBorrowSemantics(stmts []interface{}) {
    // Walk statements and check borrow rules
    for pc, stmt := range stmts {
        bc.checkStatement(pc, stmt)
    }
}

// checkStatement verifies borrow operations in a statement
func (bc *BorrowChecker) checkStatement(pc int, stmt interface{}) {
    switch s := stmt.(type) {
    case *BorrowStmt:
        bc.checkBorrowCreation(pc, s)
    case *BorrowEndStmt:
        bc.checkBorrowEnd(pc, s)
    case *UseStmt:
        bc.checkUseWithBorrows(pc, s)
    case *MoveStmt:
        bc.checkMoveWithBorrows(pc, s)
    }
}

// checkBorrowCreation verifies new borrow is valid
func (bc *BorrowChecker) checkBorrowCreation(pc int, borrow *BorrowStmt) {
    varName := borrow.Source
    isMutable := borrow.IsMutable
    
    // Check source variable exists and is owned
    sourceState := bc.ctx.GetStateAt(pc, varName)
    if sourceState == STATE_UNDEFINED {
        bc.ctx.AddError(errorf("borrow of uninitialized variable %s at PC %d",
            varName, pc))
        return
    }
    
    if sourceState == STATE_DROPPED {
        bc.ctx.AddError(errorf("borrow of dropped variable %s at PC %d (dangling borrow)",
            varName, pc))
        return
    }
    
    if sourceState == STATE_MOVED {
        bc.ctx.AddError(errorf("borrow of moved variable %s at PC %d",
            varName, pc))
        return
    }
    
    // Check for borrow conflicts
    if bc.hasBorrows(varName) {
        existingBorrows := bc.getBorrows(varName)
        
        if isMutable {
            // Mutable borrow requires NO other borrows
            if len(existingBorrows) > 0 {
                bc.ctx.AddError(errorf(
                    "cannot create mutable borrow of %s: %d existing borrow(s) at PC %d",
                    varName, len(existingBorrows), pc))
                return
            }
        } else {
            // Shared borrow conflicts with mutable borrow
            for _, existing := range existingBorrows {
                if existing.IsMutable {
                    bc.ctx.AddError(errorf(
                        "cannot create shared borrow of %s: mutable borrow active at PC %d",
                        varName, pc))
                    return
                }
            }
        }
    }
    
    // Source transitions to borrowed state
    if isMutable {
        bc.ctx.SetStateAt(pc, varName, STATE_BORROWED_MUT)
    } else {
        bc.ctx.SetStateAt(pc, varName, STATE_BORROWED_SHARED)
    }
    
    // Record borrow
    bc.recordBorrow(varName, &BorrowInfo{
        StartPC:      pc,
        IsMutable:    isMutable,
        Source:       varName,
        LifetimeName: borrow.LifetimeName,
    })
}

// checkBorrowEnd verifies borrow scope ends correctly
func (bc *BorrowChecker) checkBorrowEnd(pc int, borrowEnd *BorrowEndStmt) {
    varName := borrowEnd.Source
    
    // Verify there is an active borrow
    if !bc.hasBorrows(varName) {
        bc.ctx.AddError(errorf("borrow end: no active borrow of %s at PC %d",
            varName, pc))
        return
    }
    
    // Remove borrow and restore OWNED state
    bc.removeBorrow(varName)
    bc.ctx.SetStateAt(pc, varName, STATE_OWNED)
}

// checkUseWithBorrows verifies use is valid given active borrows
func (bc *BorrowChecker) checkUseWithBorrows(pc int, use *UseStmt) {
    varName := use.Variable
    state := bc.ctx.GetStateAt(pc, varName)
    
    if state == STATE_BORROWED_MUT {
        // Can only use through the mutable borrow reference
        if !use.ThroughBorrow {
            bc.ctx.AddError(errorf(
                "use of mutably-borrowed %s without borrow reference at PC %d",
                varName, pc))
        }
    } else if state == STATE_BORROWED_SHARED {
        // Can use through shared borrow reference
        if !use.ThroughBorrow {
            bc.ctx.AddError(errorf(
                "use of shared-borrowed %s without borrow reference at PC %d",
                varName, pc))
        }
    }
}

// checkMoveWithBorrows verifies move doesn't happen while borrowed
func (bc *BorrowChecker) checkMoveWithBorrows(pc int, move *MoveStmt) {
    varName := move.Variable
    
    if bc.hasBorrows(varName) {
        borrows := bc.getBorrows(varName)
        bc.ctx.AddError(errorf(
            "cannot move %s: %d borrow(es) still active at PC %d",
            varName, len(borrows), pc))
    }
}

// hasBorrows checks if variable has active borrows
func (bc *BorrowChecker) hasBorrows(varName string) bool {
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        _, exists := borrows[varName]
        return exists
    }
    return false
}

// getBorrows returns all active borrows of a variable
func (bc *BorrowChecker) getBorrows(varName string) []*BorrowInfo {
    var result []*BorrowInfo
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        if borrow, ok := borrows[varName]; ok {
            result = append(result, borrow)
        }
    }
    return result
}

// recordBorrow adds a new borrow to the active scope
func (bc *BorrowChecker) recordBorrow(varName string, borrow *BorrowInfo) {
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        borrows[varName] = borrow
    }
}

// removeBorrow ends an active borrow
func (bc *BorrowChecker) removeBorrow(varName string) {
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        delete(borrows, varName)
    }
}

// EnterScope pushes a new borrow scope
func (bc *BorrowChecker) EnterScope() {
    bc.ctx.BorrowStack = append(bc.ctx.BorrowStack, make(map[string]*BorrowInfo))
}

// ExitScope pops a borrow scope and verifies no dangling borrows
func (bc *BorrowChecker) ExitScope() {
    if len(bc.ctx.BorrowStack) > 1 {
        scope := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        
        // Check for dangling borrows
        for varName, borrow := range scope {
            if borrow.EndPC == 0 {
                bc.ctx.AddError(errorf(
                    "dangling borrow: %s still borrowed at scope exit",
                    varName))
            }
        }
        
        // Pop scope
        bc.ctx.BorrowStack = bc.ctx.BorrowStack[:len(bc.ctx.BorrowStack)-1]
    }
}

// VerifyNoBorrowConflicts checks all borrow rules
func (bc *BorrowChecker) VerifyNoBorrowConflicts() bool {
    return !bc.ctx.HasErrors()
}

// Simplified AST node types for borrow operations
type BorrowStmt struct {
    Source       string
    IsMutable    bool
    LifetimeName string
    RefName      string  // The reference variable created
}

type BorrowEndStmt struct {
    Source string
}

type UseStmt struct {
    Variable     string
    ThroughBorrow bool
}

type MoveStmt struct {
    Variable string
}
