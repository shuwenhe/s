package compile.internal.ownership

// move_checker.s - Verify move semantics
// 
// Checks:
// - use-after-move (ERROR)
// - double-move (ERROR)
// - move-while-borrowed (ERROR)
// - copy of non-Copy type (ERROR)

// MoveChecker analyzes move semantics in a function body
type MoveChecker struct {
    ctx *OwnershipContext
}

// NewMoveChecker creates a move semantics analyzer
func NewMoveChecker(ctx *OwnershipContext) *MoveChecker {
    return &MoveChecker{
        ctx: ctx,
    }
}

// CheckMoveSemantics performs move checking on all variable accesses
func (mc *MoveChecker) CheckMoveSemantics(stmts interface{}[]) {
    // First pass: assign initial states
    mc.initializeVariableStates(stmts)
    
    // Second pass: check all uses
    for i, stmt := range stmts {
        mc.checkStatement(i, stmt)
    }
}

// initializeVariableStates sets initial UNDEFINED state for all variables
func (mc *MoveChecker) initializeVariableStates(stmts interface{}[]) {
    // In a real implementation, walk AST to find all variable declarations
    // For now, this is a placeholder
}

// checkStatement verifies a single statement for move violations
func (mc *MoveChecker) checkStatement(pc int, stmt interface{}) {
    // Parse statement type and check accordingly
    // This is simplified - real implementation would use AST types
    
    switch s := stmt.(type) {
    case *AssignmentStmt:
        mc.checkAssignment(pc, s)
    case *CallStmt:
        mc.checkFunctionCall(pc, s)
    case *ReturnStmt:
        mc.checkReturn(pc, s)
    case *IfStmt:
        mc.checkIfStatement(pc, s)
    }
}

// checkAssignment verifies assignment doesn't violate move semantics
func (mc *MoveChecker) checkAssignment(pc int, assign *AssignmentStmt) {
    // Check RHS variables for valid states
    if assign.RHS != nil {
        mc.checkUse(pc, assign.RHS, "read")
    }
    
    // Check if this is a move assignment
    if assign.IsMove {
        // RHS must be OWNED for move
        rhsState := mc.ctx.GetStateAt(pc, assign.RHS.String())
        if rhsState != STATE_OWNED {
            mc.ctx.AddError(errorf("move %s from %s state at PC %d",
                assign.RHS, rhsState, pc))
            return
        }
        
        // Transition RHS to MOVED
        mc.ctx.SetStateAt(pc, assign.RHS.String(), STATE_MOVED)
        
        // Check RHS is not borrowed
        if mc.hasBorrow(assign.RHS.String()) {
            mc.ctx.AddError(errorf("move %s while borrowed at PC %d",
                assign.RHS, pc))
        }
    } else if assign.IsCopy {
        // Copy assignment - RHS must be Copy type or OWNED
        rhsState := mc.ctx.GetStateAt(pc, assign.RHS.String())
        typeClass := mc.ctx.classify_type(assign.RHS.String())
        
        if !typeClass.IsCopy && rhsState != STATE_OWNED {
            mc.ctx.AddError(errorf("copy %s (%s type) from %s state at PC %d",
                assign.RHS, "non-Copy", rhsState, pc))
            return
        }
        
        // Copy doesn't change state
    }
    
    // LHS becomes OWNED after assignment
    mc.ctx.SetStateAt(pc, assign.LHS, STATE_OWNED)
}

// checkFunctionCall verifies call doesn't pass invalid values
func (mc *MoveChecker) checkFunctionCall(pc int, call *CallStmt) {
    // For each argument
    for i, arg := range call.Args {
        argState := mc.ctx.GetStateAt(pc, arg.String())
        
        // Check if argument needs to be OWNED
        // (simplified - real version checks parameter type)
        if argState == STATE_MOVED {
            mc.ctx.AddError(errorf("use-after-move: argument %d (%s) at PC %d",
                i, arg, pc))
        } else if argState == STATE_UNDEFINED {
            mc.ctx.AddError(errorf("use-before-init: argument %d (%s) at PC %d",
                i, arg, pc))
        }
    }
}

// checkReturn verifies returned value is valid
func (mc *MoveChecker) checkReturn(pc int, ret *ReturnStmt) {
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

// checkIfStatement merges ownership states across branches
func (mc *MoveChecker) checkIfStatement(pc int, ifStmt *IfStmt) {
    // Check condition
    mc.checkUse(pc, ifStmt.Condition, "read")
    
    // Analyze then and else branches
    // Collect final states from each branch
    thenStates := mc.analyzeBranch(pc, ifStmt.ThenBody)
    elseStates := mc.analyzeBranch(pc, ifStmt.ElseBody)
    
    // Merge states: if different states in branches → MAYBE_MOVED
    mc.mergeBranchStates(pc, thenStates, elseStates)
}

// analyzeBranch returns variable states after executing a branch
func (mc *MoveChecker) analyzeBranch(pc int, stmts interface{}[]) map[string]OwnershipState {
    states := make(map[string]OwnershipState)
    
    for _, stmt := range stmts {
        // Track state changes
        // This is simplified
    }
    
    return states
}

// mergeBranchStates combines states from if/else branches
func (mc *MoveChecker) mergeBranchStates(pc int,
    thenStates map[string]OwnershipState,
    elseStates map[string]OwnershipState) {
    
    // For each variable in either branch
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
            // Variable only in one branch - MAYBE_MOVED
            mc.ctx.SetStateAt(pc, v, STATE_MAYBE_MOVED)
        } else if thenState == elseState {
            // Both branches same state
            mc.ctx.SetStateAt(pc, v, thenState)
        } else {
            // Branches differ - MAYBE_MOVED (conflict)
            mc.ctx.SetStateAt(pc, v, STATE_MAYBE_MOVED)
        }
    }
}

// checkUse verifies a variable is in valid state for use
func (mc *MoveChecker) checkUse(pc int, expr interface{}, useKind string) {
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

// hasBorrow checks if variable has active borrows
func (mc *MoveChecker) hasBorrow(varName string) bool {
    // Check current borrow scope
    if len(mc.ctx.BorrowStack) > 0 {
        borrows := mc.ctx.BorrowStack[len(mc.ctx.BorrowStack)-1]
        _, exists := borrows[varName]
        return exists
    }
    return false
}

// Simplified AST node types for checking
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

// errorf formats an error message
func errorf(format string, args ...interface{}) string {
    // Simple error formatting
    result := format
    for _, arg := range args {
        // Replace first %s with arg
        result = replaceFirst(result, "%s", arg.(string))
    }
    return result
}

func replaceFirst(s string, old string, new string) string {
    // Simple string replacement
    for i := 0; i < len(s); i++ {
        if i+len(old) <= len(s) && s[i:i+len(old)] == old {
            return s[:i] + new + s[i+len(old):]
        }
    }
    return s
}
