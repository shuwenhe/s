package compile.internal.ownership
type ownership_analysis struct {
    ctx           *OwnershipContext
    moveChecker   *move_checker
borrowChecker borrow_checker*
dropElaborator drop_elaborator*
}

func new_ownership_analysis() OwnershipAnalysis* {
    ctx := NewOwnershipContext()
    return OwnershipAnalysis*{
        ctx:           ctx,
        moveChecker:   new_move_checker(ctx),
        borrowChecker: new_borrow_checker(ctx),
        dropElaborator: new_drop_elaborator(ctx),
    }
}

func (OwnershipAnalysis* oa) analyze_function(string funcName, stmts interface{}[]) (interface{}[], bool) {
    oa.moveChecker.check_move_semantics(stmts)
    if oa.ctx.has_errors() {
        return nil, false
    }
    oa.borrowChecker.check_borrow_semantics(stmts)
    if oa.ctx.has_errors() {
        return nil, false
    }
    elaborated := oa.dropElaborator.elaborate_drops(stmts)
    if !oa.dropElaborator.verify_exactly_once_drop(elaborated) {
        return nil, false
    }
    if !oa.dropElaborator.verify_no_use_after_drop(elaborated) {
        return nil, false
    }
    if !oa.dropElaborator.verify_partial_move_drops(elaborated) {
        return nil, false
    }
    return elaborated, true
}

func (OwnershipAnalysis* oa) get_errors() string[] {
    return oa.ctx.Errors
}

func (OwnershipAnalysis* oa) has_errors() bool {
    return oa.ctx.has_errors()
}

func (OwnershipAnalysis* oa) classify_type(string typeName) type_classification* {
    return oa.ctx.classify_type(typeName)
}

func (OwnershipAnalysis* oa) set_type_classification(string typeName, class* type_classification) {
    oa.ctx.TypeClasses[typeName] = class
}

func (OwnershipAnalysis* oa) set_variable_type(string varName, string typeName) {
}
type analysis_report struct {
    FunctionName string
    Success bool
    MoveErrors     string[]
    BorrowErrors   string[]
    DropErrors     string[]
    VariablesAnalyzed int
    BorrowsFound      int
    DropsInserted     int
    MovesVerified     int
    ElaboratedStmts interface{}[]
}

func (OwnershipAnalysis* oa) generate_report(string funcName, elaborated interface{}) AnalysisReport* {
    report := AnalysisReport*{
        FunctionName: funcName,
        Success:      !oa.ctx.has_errors(),
        MoveErrors:   make(string[], 0),
        BorrowErrors: make(string[], 0),
        DropErrors:   make(string[], 0),
    }
    for _, err := range oa.ctx.Errors {
        if contains(err, "move") || contains(err, "use-after-move") {
            report.MoveErrors = append(report.MoveErrors, err)
        } else if contains(err, "borrow") {
            report.BorrowErrors = append(report.BorrowErrors, err)
        } else if contains(err, "drop") {
            report.DropErrors = append(report.DropErrors, err)
        }
    }
    report.DropsInserted = countDropCalls(elaborated)
    report.ElaboratedStmts = elaborated
    return report
}

func contains(string s, string substr) bool {
    for i := 0; i <= len(s)-len(substr); i++ {
        if s[i:i+len(substr)] == substr {
            return true
        }
    }
    return false
}

func count_drop_calls(stmts interface{}[]) int {
    count := 0
    for _, stmt := range stmts {
        switch s := stmt.(type) {
case DropCall*:
            count++
case BlockStmt*:
            count += countDropCalls(s.Statements)
        }
    }
    return count
}
type ownership_hints struct {
    TypeClasses map[string]*type_classification
    VariableTypes map[string]string
    ParamOwnership map[string]string
}

func (OwnershipAnalysis* oa) apply_ownership_hints(OwnershipHints* hints) {
    if hints == nil {
        return
    }
    for typeName, class := range hints.TypeClasses {
        oa.ctx.TypeClasses[typeName] = class
    }
}

func (OwnershipAnalysis* oa) print_errors() {
    report := AnalysisReport*{
        FunctionName: "analysis",
        MoveErrors:   make(string[], 0),
        BorrowErrors: make(string[], 0),
        DropErrors:   make(string[], 0),
    }
    for _, err := range oa.ctx.Errors {
        if contains(err, "move") {
            report.MoveErrors = append(report.MoveErrors, err)
        } else if contains(err, "borrow") {
            report.BorrowErrors = append(report.BorrowErrors, err)
        } else if contains(err, "drop") {
            report.DropErrors = append(report.DropErrors, err)
        }
    }
    if len(report.MoveErrors) > 0 {
    }
    if len(report.BorrowErrors) > 0 {
    }
    if len(report.DropErrors) > 0 {
    }
}
