package compile.internal

struct order_plan {
    int stmt_count
    int temp_count
    bool has_call
    bool needs_ordering
}

func order_module_name() string {
    "walk/order.s"
}

func order_module_apply() int {
    0
}

func walk_order_plan(int stmt_count, int temp_count, bool has_call) order_plan {
    order_plan {
        stmt_count: stmt_count,
        temp_count: temp_count,
        has_call: has_call,
        needs_ordering: has_call || temp_count > 0 || stmt_count > 1,
    }
}

func order_mark_temp(order_plan plan) int {
    plan.temp_count
}

func order_pop_temp(order_plan plan, int mark) order_plan {
    updated := plan
    if mark < updated.temp_count {
        updated.temp_count = mark
    }
    updated.needs_ordering = updated.has_call || updated.temp_count > 0 || updated.stmt_count > 1
    updated
}

func order_add_stmt(order_plan plan) order_plan {
    updated := plan
    updated.stmt_count = updated.stmt_count + 1
    updated.needs_ordering = true
    updated
}
