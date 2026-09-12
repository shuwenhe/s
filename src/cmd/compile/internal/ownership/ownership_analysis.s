package compile.internal.ownership
struct ownership_analysis {
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
    return oa.ctx.errors
}

func (OwnershipAnalysis* oa) has_errors() bool {
    return oa.ctx.has_errors()
}

func (OwnershipAnalysis* oa) classify_type(string typeName) type_classification* {
    return oa.ctx.classify_type(typeName)
}

func (OwnershipAnalysis* oa) set_type_classification(string typeName, class* type_classification) {
    oa.ctx.type_classes[typeName] = class
}

func (OwnershipAnalysis* oa) set_variable_type(string var_name, string typeName) {
}

struct analysis_report {
    function_name    string
    success    bool
    move_errors     string[]
    borrow_errors   string[]
    drop_errors     string[]
    variables_analyzed    int
    borrows_found    int
    drops_inserted    int
    moves_verified    int
    ElaboratedStmts interface{}[]
}

func (OwnershipAnalysis* oa) generate_report(string funcName, elaborated interface{}) analysis_report* {
    report := analysis_report*{
        function_name: funcName,
        success:      !oa.ctx.has_errors(),
        move_errors:   make(string[], 0),
        borrow_errors: make(string[], 0),
        drop_errors:   make(string[], 0),
    }
    for _, err := range oa.ctx.errors {
        if contains(err, "move") || contains(err, "use-after-move") {
            report.move_errors = append(report.move_errors, err)
        } else if contains(err, "borrow") {
            report.borrow_errors = append(report.borrow_errors, err)
        } else if contains(err, "drop") {
            report.drop_errors = append(report.drop_errors, err)
        }
    }
    report.drops_inserted = countDropCalls(elaborated)
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
            count += countDropCalls(s.statements)
        }
    }
    return count
}

struct ownership_hints {
    type_classes map[string]*type_classification
    VariableTypes map[string]string
    ParamOwnership map[string]string
}

func (OwnershipAnalysis* oa) apply_ownership_hints(OwnershipHints* hints) {
    if hints == nil {
        return
    }
    for typeName, class := range hints.type_classes {
        oa.ctx.type_classes[typeName] = class
    }
}

func (OwnershipAnalysis* oa) print_errors() {
    report := analysis_report*{
        function_name: "analysis",
        move_errors:   make(string[], 0),
        borrow_errors: make(string[], 0),
        drop_errors:   make(string[], 0),
    }
    for _, err := range oa.ctx.errors {
        if contains(err, "move") {
            report.move_errors = append(report.move_errors, err)
        } else if contains(err, "borrow") {
            report.borrow_errors = append(report.borrow_errors, err)
        } else if contains(err, "drop") {
            report.drop_errors = append(report.drop_errors, err)
        }
    }
    if len(report.move_errors) > 0 {
    }
    if len(report.borrow_errors) > 0 {
    }
    if len(report.drop_errors) > 0 {
    }
}
