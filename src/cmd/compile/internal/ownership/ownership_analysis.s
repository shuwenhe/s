package compile.internal.ownership

// ownership_analysis.s - Main ownership analysis orchestrator
//
// Coordinates the complete ownership checking pipeline:
// 1. Ownership State Analysis (identify OWNED/MOVED/BORROWED states)
// 2. Move Checker (verify move semantics)
// 3. Borrow Checker (verify borrow semantics)
// 4. Drop Elaboration (insert drop calls)

// OwnershipAnalysis orchestrates the complete ownership checking
type OwnershipAnalysis struct {
    ctx           *OwnershipContext
    moveChecker   *MoveChecker
    borrowChecker *BorrowChecker
    dropElaborator *DropElaborator
}

// NewOwnershipAnalysis creates an ownership analysis pipeline
func NewOwnershipAnalysis() *OwnershipAnalysis {
    ctx := NewOwnershipContext()
    return &OwnershipAnalysis{
        ctx:           ctx,
        moveChecker:   NewMoveChecker(ctx),
        borrowChecker: NewBorrowChecker(ctx),
        dropElaborator: NewDropElaborator(ctx),
    }
}

// AnalyzeFunction performs complete ownership analysis on a function
func (oa *OwnershipAnalysis) AnalyzeFunction(funcName string, stmts []interface{}) ([]interface{}, bool) {
    // Step 1: Check move semantics
    oa.moveChecker.CheckMoveSemantics(stmts)
    if oa.ctx.HasErrors() {
        return nil, false
    }
    
    // Step 2: Check borrow semantics
    oa.borrowChecker.CheckBorrowSemantics(stmts)
    if oa.ctx.HasErrors() {
        return nil, false
    }
    
    // Step 3: Elaborate drops (insert drop calls)
    elaborated := oa.dropElaborator.ElaborateDrops(stmts)
    
    // Step 4: Verify exactly-once drop
    if !oa.dropElaborator.VerifyExactlyOnceDrop(elaborated) {
        return nil, false
    }
    
    // Step 5: Verify no use-after-drop
    if !oa.dropElaborator.VerifyNoUseAfterDrop(elaborated) {
        return nil, false
    }
    
    // Step 6: Verify partial move drops
    if !oa.dropElaborator.VerifyPartialMoveDrops(elaborated) {
        return nil, false
    }
    
    return elaborated, true
}

// GetErrors returns all collected ownership errors
func (oa *OwnershipAnalysis) GetErrors() []string {
    return oa.ctx.Errors
}

// HasErrors checks if analysis found any violations
func (oa *OwnershipAnalysis) HasErrors() bool {
    return oa.ctx.HasErrors()
}

// ClassifyType provides type classification for ownership
func (oa *OwnershipAnalysis) ClassifyType(typeName string) *TypeClassification {
    return oa.ctx.ClassifyType(typeName)
}

// SetTypeClassification sets ownership characteristics for a type
func (oa *OwnershipAnalysis) SetTypeClassification(typeName string, class *TypeClassification) {
    oa.ctx.TypeClasses[typeName] = class
}

// SetVariableType associates a variable with its type
func (oa *OwnershipAnalysis) SetVariableType(varName string, typeName string) {
    // This would be called during semantic analysis
    // to give ownership analysis type information
}

// ========================================================================
// Ownership Analysis Report
// ========================================================================

// AnalysisReport summarizes ownership analysis results
type AnalysisReport struct {
    FunctionName string
    
    // Pass/Fail
    Success bool
    
    // Results
    MoveErrors     []string
    BorrowErrors   []string
    DropErrors     []string
    
    // Summary statistics
    VariablesAnalyzed int
    BorrowsFound      int
    DropsInserted     int
    MovesVerified     int
    
    // Elaborated code
    ElaboratedStmts []interface{}
}

// GenerateReport creates a summary of the analysis
func (oa *OwnershipAnalysis) GenerateReport(funcName string, 
    elaborated []interface{}) *AnalysisReport {
    
    report := &AnalysisReport{
        FunctionName: funcName,
        Success:      !oa.ctx.HasErrors(),
        MoveErrors:   []string{},
        BorrowErrors: []string{},
        DropErrors:   []string{},
    }
    
    // Categorize errors
    for _, err := range oa.ctx.Errors {
        if contains(err, "move") || contains(err, "use-after-move") {
            report.MoveErrors = append(report.MoveErrors, err)
        } else if contains(err, "borrow") {
            report.BorrowErrors = append(report.BorrowErrors, err)
        } else if contains(err, "drop") {
            report.DropErrors = append(report.DropErrors, err)
        }
    }
    
    // Count drops inserted
    report.DropsInserted = countDropCalls(elaborated)
    
    report.ElaboratedStmts = elaborated
    
    return report
}

// Utility function to check if string contains substring
func contains(s string, substr string) bool {
    for i := 0; i <= len(s)-len(substr); i++ {
        if s[i:i+len(substr)] == substr {
            return true
        }
    }
    return false
}

// countDropCalls counts DropCall nodes in elaborated code
func countDropCalls(stmts []interface{}) int {
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

// ========================================================================
// Integration with Semantic Analysis
// ========================================================================

// OwnershipHints provides type information to ownership analysis
type OwnershipHints struct {
    // Type → Ownership characteristics
    TypeClasses map[string]*TypeClassification
    
    // Variable → Type mapping
    VariableTypes map[string]string
    
    // Function parameters → ownership annotations
    ParamOwnership map[string]string
}

// ApplyOwnershipHints applies semantic analysis hints to the context
func (oa *OwnershipAnalysis) ApplyOwnershipHints(hints *OwnershipHints) {
    if hints == nil {
        return
    }
    
    // Register type classifications
    for typeName, class := range hints.TypeClasses {
        oa.ctx.TypeClasses[typeName] = class
    }
}

// ========================================================================
// Error Pretty-Printing
// ========================================================================

// PrintErrors outputs formatted ownership errors
func (oa *OwnershipAnalysis) PrintErrors() {
    report := &AnalysisReport{
        FunctionName: "analysis",
        MoveErrors:   []string{},
        BorrowErrors: []string{},
        DropErrors:   []string{},
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
        // Would print "Move Errors:" followed by list
    }
    if len(report.BorrowErrors) > 0 {
        // Would print "Borrow Errors:" followed by list
    }
    if len(report.DropErrors) > 0 {
        // Would print "Drop Errors:" followed by list
    }
}
