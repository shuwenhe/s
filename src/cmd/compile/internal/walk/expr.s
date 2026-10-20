package compile.internal

struct expr_plan {
    string op
    string category
    bool cheap
    bool safe
    bool may_call
}

func expr_module_name() string {
    "walk/expr.s"
}

func expr_module_apply() int {
    0
}

func walk_expr_plan(string op) expr_plan {
    expr_plan {
        op: op,
        category: expr_category(op),
        cheap: expr_is_cheap(op),
        safe: expr_is_safe(op),
        may_call: expr_may_call(op),
    }
}

func expr_category(string op) string {
    if op == "call" { return "call" }
    if op == "index" || op == "slice" || op == "dot" { return "selection" }
    if op == "add" || op == "sub" || op == "mul" || op == "div" { return "arithmetic" }
    "value"
}

func expr_is_cheap(string op) bool {
    op == "name" || op == "literal" || op == "nil" || op == "len" || op == "cap"
}

func expr_is_safe(string op) bool {
    expr_is_cheap(op) || op == "dot"
}

func expr_may_call(string op) bool {
    op == "call" || op == "append" || op == "make" || op == "new" || op == "convert"
}
