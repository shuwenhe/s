package compile.internal.ownership
type OwnershipAnalysis struct {
    ctx           *OwnershipContext
    moveChecker   *move_checker
    borrowChecker *BorrowChecker
    dropElaborator *DropElaborator
}
func NewOwnershipAnalysis() *OwnershipAnalysis {
    ctx := NewOwnershipContext()
    return &OwnershipAnalysis{
        ctx:           ctx,
        moveChecker:   new_move_checker(ctx),
        borrowChecker: NewBorrowChecker(ctx),
        dropElaborator: NewDropElaborator(ctx),
    }
}
func (oa *OwnershipAnalysis) AnalyzeFunction(funcName string, stmts interface{}[]) (interface{}[], bool) {
    oa.moveChecker.CheckMoveSemantics(stmts)
    if oa.ctx.HasErrors() {
        return nil, false
    }
    oa.borrowChecker.CheckBorrowSemantics(stmts)
    if oa.ctx.HasErrors() {
        return nil, false
    }
    elaborated := oa.dropElaborator.ElaborateDrops(stmts)
    if !oa.dropElaborator.VerifyExactlyOnceDrop(elaborated) {
        return nil, false
    }
    if !oa.dropElaborator.VerifyNoUseAfterDrop(elaborated) {
        return nil, false
    }
    if !oa.dropElaborator.VerifyPartialMoveDrops(elaborated) {
        return nil, false
    }
    return elaborated, true
}
func (oa *OwnershipAnalysis) GetErrors() string[] {
    return oa.ctx.Errors
}
func (oa *OwnershipAnalysis) HasErrors() bool {
    return oa.ctx.HasErrors()
}
func (oa *OwnershipAnalysis) classify_type(typeName string) *type_classification {
    return oa.ctx.classify_type(typeName)
}
func (oa *OwnershipAnalysis) set_type_classification(typeName string, class *type_classification) {
    oa.ctx.TypeClasses[typeName] = class
}
func (oa *OwnershipAnalysis) SetVariableType(varName string, typeName string) {
}
type AnalysisReport struct {
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
func (oa *OwnershipAnalysis) GenerateReport(funcName string, elaborated interface{}) *AnalysisReport {
    report := &AnalysisReport{
        FunctionName: funcName,
        Success:      !oa.ctx.HasErrors(),
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
func contains(s string, substr string) bool {
    for i := 0; i <= len(s)-len(substr); i++ {
        if s[i:i+len(substr)] == substr {
            return true
        }
    }
    return false
}
func countDropCalls(stmts interface{}[]) int {
    count := 0
    for _, stmt := range stmts {
        switch s := stmt.(type) {
        case *DropCall:
            count++
        case *BlockStmt:
            count += countDropCalls(s.Statements)
        }
    }
    return count
}
type OwnershipHints struct {
    TypeClasses map[string]*type_classification
    VariableTypes map[string]string
    ParamOwnership map[string]string
}
func (oa *OwnershipAnalysis) ApplyOwnershipHints(hints *OwnershipHints) {
    if hints == nil {
        return
    }
    for typeName, class := range hints.TypeClasses {
        oa.ctx.TypeClasses[typeName] = class
    }
}
func (oa *OwnershipAnalysis) PrintErrors() {
    report := &AnalysisReport{
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
