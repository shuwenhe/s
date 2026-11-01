package compile.internal.escape
import "compile.internal.mir"

func classify_expr_escape_op(string op_name) int {
    if op_name == "borrow" || op_name == "addr" {
        return 1
    }
    if op_name == "box" || op_name == "new" || op_name == "make" {
        return 2
    }
    if op_name == "call" || op_name == "dynamic_call" || op_name == "iface_call" {
        return 1
    }
    0
}

func expr_escape_level(string op_name, bool address_taken, bool returned) int {
    if op_name == "box" || op_name == "new" || op_name == "make" {
        return escape_heap
    }
    if returned {
        return escape_func
    }
    if address_taken {
        return escape_func
    }
    escape_none
}

// Count explicit heap-allocation candidates in the typed MIR. This metric
// feeds the midend report; it does not decide whether a borrow is legal.
func estimate_escape_sites_graph(mir_graph graph) int {
    sites := 0
    i := 0
    for i < len(graph.blocks) {
        j := 0
        for j < len(graph.blocks[i].statements) {
            switch graph.blocks[i].statements[j] {
                mir_statement.eval(value): {
                    if classify_expr_escape_op(value.op) == 2 { sites = sites + 1 }
                }
                mir_statement.assign(value): {
                    if classify_expr_escape_op(value.op) == 2 { sites = sites + 1 }
                }
                _ : (),
            }
            j = j + 1
        }
        i = i + 1
    }
    sites
}
