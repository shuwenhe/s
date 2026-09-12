package compile.internal.ownership
type borrow_checker struct {
ctx OwnershipContext*
}

func new_borrow_checker(OwnershipContext* ctx) borrow_checker* {
    return borrow_checker*{
        ctx: ctx,
    }
}

func (borrow_checker* bc) check_borrow_semantics(stmts interface{}[]) {
    for pc, stmt := range stmts {
        bc.check_statement(pc, stmt)
    }
}

func (borrow_checker* bc) check_statement(int pc, stmt interface{}) {
    switch s := stmt.(type) {
case BorrowStmt*:
        bc.check_borrow_creation(pc, s)
case BorrowEndStmt*:
        bc.check_borrow_end(pc, s)
case UseStmt*:
        bc.check_use_with_borrows(pc, s)
case MoveStmt*:
        bc.check_move_with_borrows(pc, s)
    }
}

func (borrow_checker* bc) check_borrow_creation(int pc, borrow* BorrowStmt) {
    varName := borrow.Source
    isMutable := borrow.IsMutable
    sourceState := bc.ctx.get_state_at(pc, varName)
    if sourceState == STATE_UNDEFINED {
        bc.ctx.add_error(errorf("borrow of uninitialized variable %s at PC %d",
            varName, pc))
        return
    }
    if sourceState == STATE_DROPPED {
        bc.ctx.add_error(errorf("borrow of dropped variable %s at PC %d (dangling borrow)",
            varName, pc))
        return
    }
    if sourceState == STATE_MOVED {
        bc.ctx.add_error(errorf("borrow of moved variable %s at PC %d",
            varName, pc))
        return
    }
    if bc.has_borrows(varName) {
        existingBorrows := bc.get_borrows(varName)
        if isMutable {
            if len(existingBorrows) > 0 {
                bc.ctx.add_error(errorf(
                    "cannot create mutable borrow of %s: %d existing borrow(s) at PC %d",
                    varName, len(existingBorrows), pc))
                return
            }
        } else {
            for _, existing := range existingBorrows {
                if existing.IsMutable {
                    bc.ctx.add_error(errorf(
                        "cannot create shared borrow of %s: mutable borrow active at PC %d",
                        varName, pc))
                    return
                }
            }
        }
    }
    if isMutable {
        bc.ctx.set_state_at(pc, varName, STATE_BORROWED_MUT)
    } else {
        bc.ctx.set_state_at(pc, varName, STATE_BORROWED_SHARED)
    }
    bc.record_borrow(varName, BorrowInfo*{
        StartPC:      pc,
        IsMutable:    isMutable,
        Source:       varName,
        LifetimeName: borrow.LifetimeName,
    })
}

func (borrow_checker* bc) check_borrow_end(int pc, borrowEnd* BorrowEndStmt) {
    varName := borrowEnd.Source
    if !bc.has_borrows(varName) {
        bc.ctx.add_error(errorf("borrow end: no active borrow of %s at PC %d",
            varName, pc))
        return
    }
    bc.remove_borrow(varName)
    bc.ctx.set_state_at(pc, varName, STATE_OWNED)
}

func (borrow_checker* bc) check_use_with_borrows(int pc, use* UseStmt) {
    varName := use.Variable
    state := bc.ctx.get_state_at(pc, varName)
    if state == STATE_BORROWED_MUT {
        if !use.ThroughBorrow {
            bc.ctx.add_error(errorf(
                "use of mutably-borrowed %s without borrow reference at PC %d",
                varName, pc))
        }
    } else if state == STATE_BORROWED_SHARED {
        if !use.ThroughBorrow {
            bc.ctx.add_error(errorf(
                "use of shared-borrowed %s without borrow reference at PC %d",
                varName, pc))
        }
    }
}

func (borrow_checker* bc) check_move_with_borrows(int pc, move* MoveStmt) {
    varName := move.Variable
    if bc.has_borrows(varName) {
        borrows := bc.get_borrows(varName)
        bc.ctx.add_error(errorf(
            "cannot move %s: %d borrow(es) still active at PC %d",
            varName, len(borrows), pc))
    }
}

func (borrow_checker* bc) has_borrows(string varName) bool {
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        _, exists := borrows[varName]
        return exists
    }
    return false
}

func (borrow_checker* bc) get_borrows(string varName) []*BorrowInfo {
    var result []*BorrowInfo
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        if borrow, ok := borrows[varName]; ok {
            result = append(result, borrow)
        }
    }
    return result
}

func (borrow_checker* bc) record_borrow(string varName, borrow* BorrowInfo) {
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        borrows[varName] = borrow
    }
}

func (borrow_checker* bc) remove_borrow(string varName) {
    if len(bc.ctx.BorrowStack) > 0 {
        borrows := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        delete(borrows, varName)
    }
}

func (borrow_checker* bc) enter_scope() {
    bc.ctx.BorrowStack = append(bc.ctx.BorrowStack, make(map[string]*BorrowInfo))
}

func (borrow_checker* bc) exit_scope() {
    if len(bc.ctx.BorrowStack) > 1 {
        scope := bc.ctx.BorrowStack[len(bc.ctx.BorrowStack)-1]
        for varName, borrow := range scope {
            if borrow.EndPC == 0 {
                bc.ctx.add_error(errorf(
                    "dangling borrow: %s still borrowed at scope exit",
                    varName))
            }
        }
        bc.ctx.BorrowStack = bc.ctx.BorrowStack[:len(bc.ctx.BorrowStack)-1]
    }
}

func (borrow_checker* bc) verify_no_borrow_conflicts() bool {
    return !bc.ctx.has_errors()
}
type borrow_stmt struct {
    Source       string
    IsMutable    bool
    LifetimeName string
    RefName      string  // The reference variable created
}
type borrow_end_stmt struct {
    Source string
}
type use_stmt struct {
    Variable     string
    ThroughBorrow bool
}
type move_stmt struct {
    Variable string
}
