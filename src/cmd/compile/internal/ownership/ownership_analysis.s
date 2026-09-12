package compile.internal.ownership
struct ownership_analysis {
    *ownership_context ctx
    *move_checker moveChecker
borrowChecker borrow_checker*
dropElaborator drop_elaborator*
}

func new_ownership_analysis() ownership_analysis* {
    ctx := new_ownership_context()
    return ownership_analysis*{
        ctx:           ctx,
        moveChecker:   new_move_checker(ctx),
        borrowChecker: new_borrow_checker(ctx),
        dropElaborator: new_drop_elaborator(ctx),
    }
}

func (ownership_analysis* oa) analyze_function(string funcName, stmts interface{}[]) (interface{}[], bool) {
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

func (ownership_analysis* oa) get_errors() string[] {
    return oa.ctx.errors
}

func (ownership_analysis* oa) has_errors() bool {
    return oa.ctx.has_errors()
}

func (ownership_analysis* oa) classify_type(string type_name) type_classification* {
    return oa.ctx.classify_type(type_name)
}

func (ownership_analysis* oa) set_type_classification(string type_name, class* type_classification) {
    oa.ctx.type_classes[type_name] = class
}

func (ownership_analysis* oa) set_variable_type(string var_name, string type_name) {
}

struct analysis_report {
    string function_name
    bool success
    string[] move_errors
    string[] borrow_errors
    string[] drop_errors
    int variables_analyzed
    int borrows_found
    int drops_inserted
    int moves_verified
    elaborated_stmts interface{}[]
}

func (ownership_analysis* oa) generate_report(string funcName, elaborated interface{}) analysis_report* {
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
    report.elaborated_stmts = elaborated
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
case drop_call*:
            count++
case block_stmt*:
            count += countDropCalls(s.statements)
        }
    }
    return count
}

struct ownership_hints {
    map[string]*type_classification type_classes
    map[string]string variable_types
    map[string]string param_ownership
}

func (ownership_analysis* oa) apply_ownership_hints(ownership_hints* hints) {
    if hints == nil {
        return
    }
    for type_name, class := range hints.type_classes {
        oa.ctx.type_classes[type_name] = class
    }
}

func (ownership_analysis* oa) print_errors() {
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