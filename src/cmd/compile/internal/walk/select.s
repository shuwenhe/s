package compile.internal.walk

struct select_plan {
    int case_count
    bool has_default
    bool needs_runtime
    string lowering
}

func select_module_name() string {
    "walk/select.s"
}

func select_module_apply() int {
    0
}

func walk_select_plan(int case_count, bool has_default) select_plan {
    select_plan {
        case_count: case_count,
        has_default: has_default,
        needs_runtime: case_count > 1,
        lowering: select_lowering(case_count, has_default),
    }
}

func select_lowering(int case_count, bool has_default) string {
    if case_count == 0 {
        return "block"
    }
    if case_count == 1 && has_default {
        return "nonblocking-single"
    }
    if case_count == 1 {
        return "single"
    }
    "runtime-select"
}

func select_uses_scase(select_plan plan) bool {
    plan.case_count > 1
}
