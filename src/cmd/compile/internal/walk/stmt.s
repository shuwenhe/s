package compile.internal

struct stmt_plan {
    string op
    bool walks_exprs
    bool walks_body
    bool terminates
}

func walk_stmt_module_name() string {
    "walk/stmt.s"
}

func walk_stmt_module_apply() int {
    0
}

func walk_stmt_plan(string op) stmt_plan {
    stmt_plan {
        op: op,
        walks_exprs: stmt_walks_exprs(op),
        walks_body: op == "if" || op == "for" || op == "range" || op == "switch" || op == "select",
        terminates: op == "return" || op == "panic" || op == "goto",
    }
}

func stmt_walks_exprs(string op) bool {
    op == "assign" || op == "return" || op == "expr" || op == "if"
        || op == "for" || op == "range" || op == "go" || op == "defer"
}

func valid_go_defer_call(string callee) bool {
    callee != "" && callee != "builtin"
}

func stmt_needs_init(stmt_plan plan) bool {
    plan.walks_exprs || plan.walks_body
}
