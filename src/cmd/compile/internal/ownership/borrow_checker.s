package compile.internal.ownership
struct borrow_checker {
ctx ownership_context*
}

func new_borrow_checker(ownership_context* ctx) borrow_checker* {
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
case borrow_stmt*:
        bc.check_borrow_creation(pc, s)
case borrow_end_stmt*:
        bc.check_borrow_end(pc, s)
case use_stmt*:
        bc.check_use_with_borrows(pc, s)
case move_stmt*:
        bc.check_move_with_borrows(pc, s)
    }
}

func (borrow_checker* bc) check_borrow_creation(int pc, borrow* borrow_stmt) {
    var_name := borrow.source
    is_mutable := borrow.is_mutable
    source_state := bc.ctx.get_state_at(pc, var_name)
    if source_state == STATE_UNDEFINED {
        bc.ctx.add_error(errorf("borrow of uninitialized variable %s at PC %d",
            var_name, pc))
        return
    }
    if source_state == STATE_DROPPED {
        bc.ctx.add_error(errorf("borrow of dropped variable %s at PC %d (dangling borrow)",
            var_name, pc))
        return
    }
    if source_state == STATE_MOVED {
        bc.ctx.add_error(errorf("borrow of moved variable %s at PC %d",
            var_name, pc))
        return
    }
    if bc.has_borrows(var_name) {
        existing_borrows := bc.get_borrows(var_name)
        if is_mutable {
            if len(existing_borrows) > 0 {
                bc.ctx.add_error(errorf(
                    "cannot create mutable borrow of %s: %d existing borrow(s) at PC %d",
                    var_name, len(existing_borrows), pc))
                return
            }
        } else {
            for _, existing := range existing_borrows {
                if existing.is_mutable {
                    bc.ctx.add_error(errorf(
                        "cannot create shared borrow of %s: mutable borrow active at PC %d",
                        var_name, pc))
                    return
                }
            }
        }
    }
    if is_mutable {
        bc.ctx.set_state_at(pc, var_name, STATE_BORROWED_MUT)
    } else {
        bc.ctx.set_state_at(pc, var_name, STATE_BORROWED_SHARED)
    }
    bc.record_borrow(var_name, borrow_info*{
        start_pc:      pc,
        is_mutable:    is_mutable,
        source:       var_name,
        lifetime_name: borrow.lifetime_name,
    })
}

func (borrow_checker* bc) check_borrow_end(int pc, borrow_end* borrow_end_stmt) {
    var_name := borrow_end.source
    if !bc.has_borrows(var_name) {
        bc.ctx.add_error(errorf("borrow end: no active borrow of %s at PC %d",
            var_name, pc))
        return
    }
    bc.remove_borrow(var_name)
    bc.ctx.set_state_at(pc, var_name, STATE_OWNED)
}

func (borrow_checker* bc) check_use_with_borrows(int pc, use* use_stmt) {
    var_name := use.variable
    state := bc.ctx.get_state_at(pc, var_name)
    if state == STATE_BORROWED_MUT {
        if !use.through_borrow {
            bc.ctx.add_error(errorf(
                "use of mutably-borrowed %s without borrow reference at PC %d",
                var_name, pc))
        }
    } else if state == STATE_BORROWED_SHARED {
        if !use.through_borrow {
            bc.ctx.add_error(errorf(
                "use of shared-borrowed %s without borrow reference at PC %d",
                var_name, pc))
        }
    }
}

func (borrow_checker* bc) check_move_with_borrows(int pc, move* move_stmt) {
    var_name := move.variable
    if bc.has_borrows(var_name) {
        borrows := bc.get_borrows(var_name)
        bc.ctx.add_error(errorf(
            "cannot move %s: %d borrow(es) still active at PC %d",
            var_name, len(borrows), pc))
    }
}

func (borrow_checker* bc) has_borrows(string var_name) bool {
    if len(bc.ctx.borrow_stack) > 0 {
        borrows := bc.ctx.borrow_stack[len(bc.ctx.borrow_stack)-1]
        _, exists := borrows[var_name]
        return exists
    }
    return false
}

func (borrow_checker* bc) get_borrows(string var_name) []*borrow_info {
    var result []*borrow_info
    if len(bc.ctx.borrow_stack) > 0 {
        borrows := bc.ctx.borrow_stack[len(bc.ctx.borrow_stack)-1]
        if borrow, ok := borrows[var_name]; ok {
            result = append(result, borrow)
        }
    }
    return result
}

func (borrow_checker* bc) record_borrow(string var_name, borrow* borrow_info) {
    if len(bc.ctx.borrow_stack) > 0 {
        borrows := bc.ctx.borrow_stack[len(bc.ctx.borrow_stack)-1]
        borrows[var_name] = borrow
    }
}

func (borrow_checker* bc) remove_borrow(string var_name) {
    if len(bc.ctx.borrow_stack) > 0 {
        borrows := bc.ctx.borrow_stack[len(bc.ctx.borrow_stack)-1]
        delete(borrows, var_name)
    }
}

func (borrow_checker* bc) enter_scope() {
    bc.ctx.borrow_stack = append(bc.ctx.borrow_stack, make(map[string]*borrow_info))
}

func (borrow_checker* bc) exit_scope() {
    if len(bc.ctx.borrow_stack) > 1 {
        scope := bc.ctx.borrow_stack[len(bc.ctx.borrow_stack)-1]
        for var_name, borrow := range scope {
            if borrow.end_pc == 0 {
                bc.ctx.add_error(errorf(
                    "dangling borrow: %s still borrowed at scope exit",
                    var_name))
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
    ref_name      string
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
