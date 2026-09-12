package compile.internal.ownership
type move_checker struct {
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
    case AssignmentStmt*:
        mc.check_assignment(pc, s)
    case CallStmt*:
        mc.check_function_call(pc, s)
    case ReturnStmt*:
        mc.check_return(pc, s)
    case IfStmt*:
        mc.check_if_statement(pc, s)
    }
}

func (move_checker* mc) check_assignment(int pc, assign* AssignmentStmt) {
    if assign.rhs != nil {
        mc.check_use(pc, assign.rhs, "read")
    }
    if assign.is_move {
        rhsState := mc.ctx.get_state_at(pc, assign.rhs.string())
        if rhsState != STATE_OWNED {
            mc.ctx.add_error(errorf("move %s from %s state at PC %d",
                assign.rhs, rhsState, pc))
            return
        }
        mc.ctx.set_state_at(pc, assign.rhs.string(), STATE_MOVED)
        if mc.has_borrow(assign.rhs.string()) {
            mc.ctx.add_error(errorf("move %s while borrowed at PC %d",
                assign.rhs, pc))
        }
    } else if assign.is_copy {
        rhsState := mc.ctx.get_state_at(pc, assign.rhs.string())
        typeClass := mc.ctx.classify_type(assign.rhs.string())
        if !typeClass.is_copy && rhsState != STATE_OWNED {
            mc.ctx.add_error(errorf("copy %s (%s type) from %s state at PC %d",
                assign.rhs, "non-Copy", rhsState, pc))
            return
        }
    }
    mc.ctx.set_state_at(pc, assign.lhs, STATE_OWNED)
}

func (move_checker* mc) check_function_call(int pc, call* CallStmt) {
    for i, arg := range call.Args {
        argState := mc.ctx.get_state_at(pc, arg.string())
        if argState == STATE_MOVED {
            mc.ctx.add_error(errorf("use-after-move: argument %d (%s) at PC %d",
                i, arg, pc))
        } else if argState == STATE_UNDEFINED {
            mc.ctx.add_error(errorf("use-before-init: argument %d (%s) at PC %d",
                i, arg, pc))
        }
    }
}

func (move_checker* mc) check_return(int pc, ret* ReturnStmt) {
    if ret.Value == nil {
        return
    }
    returnState := mc.ctx.get_state_at(pc, ret.Value.string())
    if returnState == STATE_MOVED {
        mc.ctx.add_error(errorf("return-after-move: %s at PC %d",
            ret.Value, pc))
    } else if returnState == STATE_UNDEFINED {
        mc.ctx.add_error(errorf("return-uninitialized: %s at PC %d",
            ret.Value, pc))
    }
}

func (move_checker* mc) check_if_statement(int pc, ifStmt* IfStmt) {
    mc.check_use(pc, ifStmt.condition, "read")
    thenStates := mc.analyze_branch(pc, ifStmt.ThenBody)
    elseStates := mc.analyze_branch(pc, ifStmt.ElseBody)
    mc.merge_branch_states(pc, thenStates, elseStates)
}

func (move_checker* mc) analyze_branch(int pc, stmts interface{}[]) map[string]OwnershipState {
    states := make(map[string]OwnershipState)
    for _, stmt := range stmts {
    }
    return states
}

func (move_checker* mc) merge_branch_states(int pc,
    thenStates map[string]OwnershipState,
    elseStates map[string]OwnershipState) {
    allVars := make(map[string]bool)
    for v := range thenStates {
        allVars[v] = true
    }
    for v := range elseStates {
        allVars[v] = true
    }
    for v := range allVars {
        thenState, thenOk := thenStates[v]
        elseState, elseOk := elseStates[v]
        if !thenOk || !elseOk {
            mc.ctx.set_state_at(pc, v, STATE_MAYBE_MOVED)
        } else if thenState == elseState {
            mc.ctx.set_state_at(pc, v, thenState)
        } else {
            mc.ctx.set_state_at(pc, v, STATE_MAYBE_MOVED)
        }
    }
}

func (move_checker* mc) check_use(int pc, expr interface{}, string useKind) {
    exprStr := expr.(interface{}).string()
    state := mc.ctx.get_state_at(pc, exprStr)
    switch useKind {
    case "read":
        if state == STATE_MOVED {
            mc.ctx.add_error(errorf("use-after-move: reading %s at PC %d", exprStr, pc))
        } else if state == STATE_DROPPED {
            mc.ctx.add_error(errorf("use-after-drop: reading %s at PC %d", exprStr, pc))
        } else if state == STATE_UNDEFINED {
            mc.ctx.add_error(errorf("use-before-init: reading %s at PC %d", exprStr, pc))
        }
    case "move":
        if state != STATE_OWNED {
            mc.ctx.add_error(errorf("cannot move %s from %s state at PC %d", 
                exprStr, state, pc))
        }
    }
}

func (move_checker* mc) has_borrow(string varName) bool {
    if len(mc.ctx.borrow_stack) > 0 {
        borrows := mc.ctx.borrow_stack[len(mc.ctx.borrow_stack)-1]
        _, exists := borrows[varName]
        return exists
    }
    return false
}
type assignment_stmt struct {
    lhs    string
    rhs    interface{}
    is_move    bool
    is_copy    bool
}
type call_stmt struct {
    func    string
    Args interface{}[]
}
type return_stmt struct {
    Value interface{}
}
type if_stmt struct {
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
