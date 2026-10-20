package compile.internal

struct assign_plan {
    string op
    int lhs_count
    int rhs_count
    bool needs_conversion
    bool reads_memory
    bool is_return
}

func assign_module_name() string {
    "walk/assign.s"
}

func assign_module_apply() int {
    0
}

func walk_assign_plan(string op, int lhs_count, int rhs_count) assign_plan {
    assign_plan {
        op: op,
        lhs_count: lhs_count,
        rhs_count: rhs_count,
        needs_conversion: lhs_count == rhs_count,
        reads_memory: assign_reads_memory(op),
        is_return: op == "return",
    }
}

func assign_reads_memory(string op) bool {
    op == "mapread" || op == "recv" || op == "call" || op == "append"
}

func assign_is_multi(assign_plan plan) bool {
    plan.lhs_count > 1 || plan.rhs_count > 1
}

func assign_is_compatible(assign_plan plan) bool {
    plan.lhs_count == plan.rhs_count || plan.rhs_count == 1
}

func assign_runtime_helper(assign_plan plan) string {
    if plan.op == "mapread" {
        return "mapaccess2"
    }
    if plan.op == "recv" {
        return "chanrecv2"
    }
    if plan.op == "append" {
        return "growslice"
    }
    ""
}
