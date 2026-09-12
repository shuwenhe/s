package compile.internal.ownership
type BorrowChecker struct {
ctx OwnershipContext*
}

func NewBorrowChecker(OwnershipContext* ctx) BorrowChecker* {
    return BorrowChecker*{
        ctx: ctx,
    }
}

func (BorrowChecker* bc) CheckBorrowSemantics(stmts interface{}[]) {
    for pc, stmt := range stmts {
        bc.checkStatement(pc, stmt)
    }
}

func (BorrowChecker* bc) checkStatement(pc int, stmt interface{}) {
    switch s := stmt.(type) {
case BorrowStmt*:
        bc.checkBorrowCreation(pc, s)
case BorrowEndStmt*:
        bc.checkBorrowEnd(pc, s)
case UseStmt*:
        bc.checkUseWithBorrows(pc, s)
case MoveStmt*:
        bc.checkMoveWithBorrows(pc, s)
    }
}

func (BorrowChecker* bc) checkBorrowCreation(pc int, borrow* BorrowStmt) {
    varName := borrow.Source
    isMutable := borrow.IsMutable
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
    if bc.hasBorrows(varName) {
        existingBorrows := bc.getBorrows(varName)
        if isMutable {
            if len(existingBorrows) > 0 {
                bc.ctx.AddError(errorf(
                    "cannot create mutable borrow of %s: %d existing borrow(s) at PC %d",
                    varName, len(existingBorrows), pc))
                return
            }
        } else {
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
    if isMutable {
        bc.ctx.SetStateAt(pc, varName, STATE_BORROWED_MUT)
    } else {
        bc.ctx.SetStateAt(pc, varName, STATE_BORROWED_SHARED)
    }
    bc.recordBorrow(varName, BorrowInfo*{
        StartPC:      pc,
        IsMutable:    isMutable,
        Source:       varName,
        LifetimeName: borrow.LifetimeName,
    })
}

func (BorrowChecker* bc) checkBorrowEnd(pc int, borrowEnd* BorrowEndStmt) {
    varName := borrowEnd.Source
    if !bc.hasBorrows(varName) {
        bc.ctx.AddError(errorf("borrow end: no active borrow of %s at PC %d",
            varName, pc))
        return
    }
    bc.removeBorrow(varName)
    bc.ctx.SetStateAt(pc, varName, STATE_OWNED)
}

func (BorrowChecker* bc) checkUseWithBorrows(pc int, use* UseStmt) {
    varName := use.Variable
    state := bc.ctx.GetStateAt(pc, varName)
    if state == STATE_BORROWED_MUT {
        if !use.ThroughBorrow {
            bc.ctx.AddError(errorf(
                "use of mutably-borrowed %s without borrow reference at PC %d",
                varName, pc))
        }
    } else if state == STATE_BORROWED_SHARED {
        if !use.ThroughBorrow {
            bc.ctx.AddError(errorf(
                "use of shared-borrowed %s without borrow reference at PC %d",
                varName, pc))
        }
    }
}

func (BorrowChecker* bc) checkMoveWithBorrows(pc int, move* MoveStmt) {
    varName := move.Variable
    if bc.hasBorrows(varName) {
        borrows := bc.getBorrows(varName)
        bc.ctx.AddError(errorf(
            "cannot move %s: %d borrow(es) still active at PC %d",
            varName, len(borrows), pc))
    }
}

func (BorrowChecker* bc) hasBorrows(varName string) bool {
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        _, exists := borrows[varName]
        return exists
    }
    return false
}

func (BorrowChecker* bc) getBorrows(varName string) []*BorrowInfo {
    var result []*BorrowInfo
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        if borrow, ok := borrows[varName]; ok {
            result = append(result, borrow)
        }
    }
    return result
}

func (BorrowChecker* bc) recordBorrow(varName string, borrow* BorrowInfo) {
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        borrows[varName] = borrow
    }
}

func (BorrowChecker* bc) removeBorrow(varName string) {
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        delete(borrows, varName)
    }
}

func (BorrowChecker* bc) EnterScope() {
    bc.ctx.BorrowStack = append(bc.ctx.BorrowStack, make(map[string]*BorrowInfo))
}

func (BorrowChecker* bc) ExitScope() {
    if len(bc.ctx.BorrowStack) > 1 {
        scope := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        for varName, borrow := range scope {
            if borrow.EndPC == 0 {
                bc.ctx.AddError(errorf(
                    "dangling borrow: %s still borrowed at scope exit",
                    varName))
            }
        }
        bc.ctx.BorrowStack = bc.ctx.BorrowStack[:len(bc.ctx.BorrowStack)-1]
    }
}

func (BorrowChecker* bc) VerifyNoBorrowConflicts() bool {
    return !bc.ctx.HasErrors()
}
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
