package compile.internal.ownership
struct borrow_checker {
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
    varName := borrow.source
    isMutable := borrow.is_mutable
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
                if existing.is_mutable {
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
    bc.record_borrow(varName, borrow_info*{
        start_pc:      pc,
        is_mutable:    isMutable,
        source:       varName,
        lifetime_name: borrow.lifetime_name,
    })
}

func (borrow_checker* bc) check_borrow_end(int pc, borrowEnd* BorrowEndStmt) {
    varName := borrowEnd.source
    if !bc.has_borrows(varName) {
        bc.ctx.add_error(errorf("borrow end: no active borrow of %s at PC %d",
            varName, pc))
        return
    }
    bc.remove_borrow(varName)
    bc.ctx.set_state_at(pc, varName, STATE_OWNED)
}

func (borrow_checker* bc) check_use_with_borrows(int pc, use* UseStmt) {
    varName := use.variable
    state := bc.ctx.get_state_at(pc, varName)
    if state == STATE_BORROWED_MUT {
        if !use.through_borrow {
            bc.ctx.add_error(errorf(
                "use of mutably-borrowed %s without borrow reference at PC %d",
                varName, pc))
        }
    } else if state == STATE_BORROWED_SHARED {
        if !use.through_borrow {
            bc.ctx.add_error(errorf(
                "use of shared-borrowed %s without borrow reference at PC %d",
                varName, pc))
        }
    }
}

func (borrow_checker* bc) check_move_with_borrows(int pc, move* MoveStmt) {
    varName := move.variable
    if bc.has_borrows(varName) {
        borrows := bc.get_borrows(varName)
        bc.ctx.add_error(errorf(
            "cannot move %s: %d borrow(es) still active at PC %d",
            varName, len(borrows), pc))
    }
}

func (borrow_checker* bc) has_borrows(string varName) bool {
    if len(bc.ctx.borrow_stack) > 0 {
        borrows := bc.ctx.borrow_stack[len(bc.ctx.borrow_stack)-1]
        _, exists := borrows[varName]
        return exists
    }
    return false
}

func (borrow_checker* bc) get_borrows(string varName) []*borrow_info {
    var result []*borrow_info
    if len(bc.ctx.borrow_stack) > 0 {
        borrows := bc.ctx.borrow_stack[len(bc.ctx.borrow_stack)-1]
        if borrow, ok := borrows[varName]; ok {
            result = append(result, borrow)
        }
    }
    return result
}

func (borrow_checker* bc) record_borrow(string varName, borrow* borrow_info) {
    if len(bc.ctx.borrow_stack) > 0 {
        borrows := bc.ctx.borrow_stack[len(bc.ctx.borrow_stack)-1]
        borrows[varName] = borrow
    }
}

func (borrow_checker* bc) remove_borrow(string varName) {
    if len(bc.ctx.borrow_stack) > 0 {
        borrows := bc.ctx.borrow_stack[len(bc.ctx.borrow_stack)-1]
        delete(borrows, varName)
    }
}

func (borrow_checker* bc) enter_scope() {
    bc.ctx.borrow_stack = append(bc.ctx.borrow_stack, make(map[string]*borrow_info))
}

func (borrow_checker* bc) exit_scope() {
    if len(bc.ctx.borrow_stack) > 1 {
        scope := bc.ctx.borrow_stack[len(bc.ctx.borrow_stack)-1]
        for varName, borrow := range scope {
            if borrow.end_pc == 0 {
                bc.ctx.add_error(errorf(
                    "dangling borrow: %s still borrowed at scope exit",
                    varName))
            }
        }
        bc.ctx.borrow_stack = bc.ctx.borrow_stack[:len(bc.ctx.borrow_stack)-1]
    }
}

func (borrow_checker* bc) verify_no_borrow_conflicts() bool {
    return !bc.ctx.has_errors()
}
struct borrow_stmt {
    source    string
    is_mutable    bool
    lifetime_name string
    ref_name      string  // The reference variable created
}
struct borrow_end_stmt {
    source    string
}
struct use_stmt {
    variable     string
    through_borrow bool
}
struct move_stmt {
    variable string
}
