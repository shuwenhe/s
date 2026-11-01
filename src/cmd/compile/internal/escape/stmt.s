package compile.internal.escape

func classify_stmt_escape_op(string op_name) int {
    if op_name == "return" {
        return 2
    }
    if op_name == "assign" || op_name == "store" {
        return 1
    }
    0
}

func record_return_escape(escape_analysis analysis, int variable_id) {
    _ = analysis.leaks.result
}
