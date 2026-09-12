package compile.internal.ownership
type move_checker struct {
    ctx OwnershipContext*
}

func new_move_checker(OwnershipContext* ctx) move_checker* {
    return move_checker*{
        ctx: ctx,
    }
}

func (move_checker* mc) CheckMoveSemantics(stmts interface{}[]) {
    mc.initializeVariableStates(stmts)
    for i, stmt := range stmts {
        mc.checkStatement(i, stmt)
    }
}

func (move_checker* mc) initializeVariableStates(stmts interface{}[]) {
}

func (move_checker* mc) checkStatement(pc int, stmt interface{}) {
    switch s := stmt.(type) {
    case AssignmentStmt*:
        mc.checkAssignment(pc, s)
    case CallStmt*:
        mc.check_function_call(pc, s)
    case ReturnStmt*:
        mc.checkReturn(pc, s)
    case IfStmt*:
        mc.checkIfStatement(pc, s)
    }
}

func (move_checker* mc) checkAssignment(pc int, assign* AssignmentStmt) {
    if assign.RHS != nil {
        mc.checkUse(pc, assign.RHS, "read")
    }
    if assign.IsMove {
        rhsState := mc.ctx.GetStateAt(pc, assign.RHS.String())
        if rhsState != STATE_OWNED {
            mc.ctx.AddError(errorf("move %s from %s state at PC %d",
                assign.RHS, rhsState, pc))
            return
        }
        mc.ctx.SetStateAt(pc, assign.RHS.String(), STATE_MOVED)
        if mc.hasBorrow(assign.RHS.String()) {
            mc.ctx.AddError(errorf("move %s while borrowed at PC %d",
                assign.RHS, pc))
        }
    } else if assign.IsCopy {
        rhsState := mc.ctx.GetStateAt(pc, assign.RHS.String())
        typeClass := mc.ctx.classify_type(assign.RHS.String())
        if !typeClass.IsCopy && rhsState != STATE_OWNED {
            mc.ctx.AddError(errorf("copy %s (%s type) from %s state at PC %d",
                assign.RHS, "non-Copy", rhsState, pc))
            return
        }
    }
    mc.ctx.SetStateAt(pc, assign.LHS, STATE_OWNED)
}

func (move_checker* mc) check_function_call(pc int, call* CallStmt) {
    for i, arg := range call.Args {
        argState := mc.ctx.GetStateAt(pc, arg.String())
        if argState == STATE_MOVED {
            mc.ctx.AddError(errorf("use-after-move: argument %d (%s) at PC %d",
                i, arg, pc))
        } else if argState == STATE_UNDEFINED {
            mc.ctx.AddError(errorf("use-before-init: argument %d (%s) at PC %d",
                i, arg, pc))
        }
    }
}

func (move_checker* mc) checkReturn(pc int, ret* ReturnStmt) {
    if ret.Value == nil {
        return
    }
    returnState := mc.ctx.GetStateAt(pc, ret.Value.String())
    if returnState == STATE_MOVED {
        mc.ctx.AddError(errorf("return-after-move: %s at PC %d",
            ret.Value, pc))
    } else if returnState == STATE_UNDEFINED {
        mc.ctx.AddError(errorf("return-uninitialized: %s at PC %d",
            ret.Value, pc))
    }
}

func (move_checker* mc) checkIfStatement(pc int, ifStmt* IfStmt) {
    mc.checkUse(pc, ifStmt.Condition, "read")
    thenStates := mc.analyzeBranch(pc, ifStmt.ThenBody)
    elseStates := mc.analyzeBranch(pc, ifStmt.ElseBody)
    mc.mergeBranchStates(pc, thenStates, elseStates)
}

func (move_checker* mc) analyzeBranch(pc int, stmts interface{}[]) map[string]OwnershipState {
    states := make(map[string]OwnershipState)
    for _, stmt := range stmts {
    }
    return states
}

func (move_checker* mc) mergeBranchStates(pc int,
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
            mc.ctx.SetStateAt(pc, v, STATE_MAYBE_MOVED)
        } else if thenState == elseState {
            mc.ctx.SetStateAt(pc, v, thenState)
        } else {
            mc.ctx.SetStateAt(pc, v, STATE_MAYBE_MOVED)
        }
    }
}

func (move_checker* mc) checkUse(pc int, expr interface{}, useKind string) {
    exprStr := expr.(interface{}).String()
    state := mc.ctx.GetStateAt(pc, exprStr)
    switch useKind {
    case "read":
        if state == STATE_MOVED {
            mc.ctx.AddError(errorf("use-after-move: reading %s at PC %d", exprStr, pc))
        } else if state == STATE_DROPPED {
            mc.ctx.AddError(errorf("use-after-drop: reading %s at PC %d", exprStr, pc))
        } else if state == STATE_UNDEFINED {
            mc.ctx.AddError(errorf("use-before-init: reading %s at PC %d", exprStr, pc))
        }
    case "move":
        if state != STATE_OWNED {
            mc.ctx.AddError(errorf("cannot move %s from %s state at PC %d", 
                exprStr, state, pc))
        }
    }
}

func (move_checker* mc) hasBorrow(varName string) bool {
    if len(mc.ctx.BorrowStack) > 0 {
        borrows := mc.ctx.BorrowStack[len(mc.ctx.BorrowStack)-1]
        _, exists := borrows[varName]
        return exists
    }
    return false
}
type AssignmentStmt struct {
    LHS    string
    RHS    interface{}
    IsMove bool
    IsCopy bool
}
type CallStmt struct {
    Func string
    Args interface{}[]
}
type ReturnStmt struct {
    Value interface{}
}
type IfStmt struct {
    Condition interface{}
    ThenBody  interface{}[]
    ElseBody  interface{}[]
}

func errorf(format string, args ...interface{}) string {
    result := format
    for _, arg := range args {
        result = replaceFirst(result, "%s", arg.(string))
    }
    return result
}

func replaceFirst(s string, old string, new string) string {
    for i := 0; i < len(s); i++ {
        if i+len(old) <= len(s) && s[i:i+len(old)] == old {
            return s[:i] + new + s[i+len(old):]
        }
    }
    return s
}
