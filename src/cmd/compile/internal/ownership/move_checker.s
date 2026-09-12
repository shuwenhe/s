package compile.internal.ownership
struct move_checker {
    ctx OwnershipContext*
}

func new_move_checker(OwnershipContext* ctx) move_checker* {
    return move_checker*{
        ctx: ctx,
    }
}

func (move_checker* mc) check_move_semantics(stmts interface{}[]) {
    mc.initialize_variable_states(stmts)
    for i, stmt := range stmts {
        mc.check_statement(i, stmt)
    }
}

func (move_checker* mc) initialize_variable_states(stmts interface{}[]) {
}

func (move_checker* mc) check_statement(int pc, stmt interface{}) {
    switch s := stmt.(type) {
    case assignment_stmt*:
        mc.check_assignment(pc, s)
    case call_stmt*:
        mc.check_function_call(pc, s)
    case ReturnStmt*:
        mc.check_return(pc, s)
    case if_stmt*:
        mc.check_if_statement(pc, s)
    }
}

func (move_checker* mc) check_assignment(int pc, assign* assignment_stmt) {
    if assign.rhs != nil {
        mc.check_use(pc, assign.rhs, "read")
    }
    if assign.is_move {
        rhs_state := mc.ctx.get_state_at(pc, assign.rhs.string())
        if rhs_state != STATE_OWNED {
            mc.ctx.add_error(errorf("move %s from %s state at PC %d",
                assign.rhs, rhs_state, pc))
            return
        }
        mc.ctx.set_state_at(pc, assign.rhs.string(), STATE_MOVED)
        if mc.has_borrow(assign.rhs.string()) {
            mc.ctx.add_error(errorf("move %s while borrowed at PC %d",
                assign.rhs, pc))
        }
    } else if assign.is_copy {
        rhs_state := mc.ctx.get_state_at(pc, assign.rhs.string())
        type_class := mc.ctx.classify_type(assign.rhs.string())
        if !type_class.is_copy && rhs_state != STATE_OWNED {
            mc.ctx.add_error(errorf("copy %s (%s type) from %s state at PC %d",
                assign.rhs, "non-Copy", rhs_state, pc))
            return
        }
    }
    mc.ctx.set_state_at(pc, assign.lhs, STATE_OWNED)
}

func (move_checker* mc) check_function_call(int pc, call* call_stmt) {
    for i, arg := range call.args {
        arg_state := mc.ctx.get_state_at(pc, arg.string())
        if arg_state == STATE_MOVED {
            mc.ctx.add_error(errorf("use-after-move: argument %d (%s) at PC %d",
                i, arg, pc))
        } else if arg_state == STATE_UNDEFINED {
            mc.ctx.add_error(errorf("use-before-init: argument %d (%s) at PC %d",
                i, arg, pc))
        }
    }
}

func (move_checker* mc) check_return(int pc, ret* ReturnStmt) {
    if ret.value == nil {
        return
    }
    return_state := mc.ctx.get_state_at(pc, ret.value.string())
    if return_state == STATE_MOVED {
        mc.ctx.add_error(errorf("return-after-move: %s at PC %d",
            ret.value, pc))
    } else if return_state == STATE_UNDEFINED {
        mc.ctx.add_error(errorf("return-uninitialized: %s at PC %d",
            ret.value, pc))
    }
}

func (move_checker* mc) check_if_statement(int pc, ifStmt* if_stmt) {
    mc.check_use(pc, ifStmt.condition, "read")
    then_states := mc.analyze_branch(pc, ifStmt.ThenBody)
    else_states := mc.analyze_branch(pc, ifStmt.ElseBody)
    mc.merge_branch_states(pc, then_states, else_states)
}

func (move_checker* mc) analyze_branch(int pc, stmts interface{}[]) map[string]OwnershipState {
    states := make(map[string]OwnershipState)
    for _, stmt := range stmts {
    }
    return states
}

func (move_checker* mc) merge_branch_states(int pc,
    then_states map[string]OwnershipState,
    else_states map[string]OwnershipState) {
    all_vars := make(map[string]bool)
    for v := range then_states {
        all_vars[v] = true
    }
    for v := range else_states {
        all_vars[v] = true
    }
    for v := range all_vars {
        thenState, then_ok := then_states[v]
        elseState, else_ok := else_states[v]
        if !then_ok || !else_ok {
            mc.ctx.set_state_at(pc, v, STATE_MAYBE_MOVED)
        } else if thenState == elseState {
            mc.ctx.set_state_at(pc, v, thenState)
        } else {
            mc.ctx.set_state_at(pc, v, STATE_MAYBE_MOVED)
        }
    }
}

func (move_checker* mc) check_use(int pc, expr interface{}, string useKind) {
    expr_str := expr.(interface{}).string()
    state := mc.ctx.get_state_at(pc, expr_str)
    switch useKind {
    case "read":
        if state == STATE_MOVED {
            mc.ctx.add_error(errorf("use-after-move: reading %s at PC %d", expr_str, pc))
        } else if state == STATE_DROPPED {
            mc.ctx.add_error(errorf("use-after-drop: reading %s at PC %d", expr_str, pc))
        } else if state == STATE_UNDEFINED {
            mc.ctx.add_error(errorf("use-before-init: reading %s at PC %d", expr_str, pc))
        }
    case "move":
        if state != STATE_OWNED {
            mc.ctx.add_error(errorf("cannot move %s from %s state at PC %d", 
                expr_str, state, pc))
        }
    }
}

func (move_checker* mc) has_borrow(string var_name) bool {
    if len(mc.ctx.borrow_stack) > 0 {
        borrows := mc.ctx.borrow_stack[len(mc.ctx.borrow_stack)-1]
        _, exists := borrows[var_name]
        return exists
    }
    return false
}

struct assignment_stmt {
    lhs    string
    rhs    interface{}
    is_move    bool
    is_copy    bool
}

struct call_stmt {
    func    string
    Args interface{}[]
}

struct return_stmt {
    Value interface{}
}

struct if_stmt {
    Condition interface{}
    ThenBody  interface{}[]
    ElseBody  interface{}[]
}

func errorf(string format, args ...interface{}) string {
    result := format
    for _, arg := range args {
        result = replaceFirst(result, "%s", arg.(string))
    }
    return result
}

func replace_first(string s, string old, string new) string {
    for i := 0; i < len(s); i++ {
        if i+len(old) <= len(s) && s[i:i+len(old)] == old {
            return s[:i] + new + s[i+len(old):]
        }
    }
    return s
}
