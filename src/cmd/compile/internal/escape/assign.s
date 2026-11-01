package compile.internal.escape

func classify_assign_escape_op(string op_name) int {
    if op_name == "store" {
        return 2
    }
    if op_name == "return" {
        return 2
    }
    if op_name == "addr" || op_name == "borrow" {
        return 1
    }
    if op_name == "move" || op_name == "copy" {
        return 0
    }
    0
}

func record_escape_assignment(escape_analysis analysis, int dst, int src, string op_name) {
    derefs := 0
    if op_name == "addr" || op_name == "borrow" {
        derefs = -1
    }
    add_escape_edge(analysis.graph, src, dst, derefs, op_name)
}
