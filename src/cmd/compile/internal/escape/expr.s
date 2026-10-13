package compile.internal.escape

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
